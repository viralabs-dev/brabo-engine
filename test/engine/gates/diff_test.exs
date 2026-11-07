defmodule Engine.Gates.DiffTest do
  # RN-664 (AT-250) — o diff que o gate julga é calculado contra a branch de
  # TRABALHO (`main`), a mesma que a PR do dev agent mira, e não contra a
  # `default_branch` do provider. E a linha de contexto que o QA lê diz a mesma
  # branch.
  use Engine.DataCase, async: true

  alias Engine.Gates.Diff
  alias Engine.Harness.ProjectContext

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "brabo-diff-#{System.os_time(:microsecond)}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp git!(cd, args) do
    {out, 0} = System.cmd("git", args, cd: cd, stderr_to_stdout: true)
    out
  end

  defp commit!(dir, arquivo, conteudo) do
    File.write!(Path.join(dir, arquivo), conteudo)
    git!(dir, ["add", "-A"])
    git!(dir, ["-c", "user.email=t@t.com", "-c", "user.name=t", "commit", "-m", arquivo])
  end

  defp insert_repo!(project_id) do
    Repo.query!(
      """
      INSERT INTO public.project_repositories
        (id, project_id, provider, external_id, url, default_branch, visibility, provisioned_by)
      VALUES ($1, $2, 'local', '/tmp/x.git', 'file:///tmp/x.git', 'main', 'private', $3)
      """,
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        Ecto.UUID.dump!(project_id),
        Ecto.UUID.dump!(Ecto.UUID.generate())
      ]
    )
  end

  # Uma branch `legado` com um commit que a `main` (o trunk) NÃO tem, e o
  # worktree do agente nascido da `main` com a mudança dele.
  defp repo_com_main_e_dev!(root) do
    dir = Path.join(root, "wt")
    File.mkdir_p!(dir)
    git!(dir, ["init", "--initial-branch=legado"])
    commit!(dir, "README.md", "base")
    git!(dir, ["branch", "main"])
    commit!(dir, "SO_NO_LEGADO.md", "só no legado")
    git!(dir, ["checkout", "-b", "feature/task-a", "main"])
    commit!(dir, "MUDANCA_DO_AGENTE.md", "trabalho do agente")
    dir
  end

  test "o diff é `main...HEAD`: só a mudança do agente, nada da `main`", %{root: root} do
    project_id = Ecto.UUID.generate()
    insert_repo!(project_id)
    dir = repo_com_main_e_dev!(root)

    assert {:ok, diff} = Diff.compute(project_id, dir)
    assert Diff.changed_paths(diff) == ["MUDANCA_DO_AGENTE.md"]
  end

  test "repositório sem `main`: o diff FALHA nomeando a revisão, sem cair na `main`", %{
    root: root
  } do
    project_id = Ecto.UUID.generate()
    insert_repo!(project_id)
    dir = Path.join(root, "sem-dev")
    File.mkdir_p!(dir)
    git!(dir, ["init", "--initial-branch=legado"])
    commit!(dir, "README.md", "base")

    assert {:error, motivo} = Diff.compute(project_id, dir)
    assert motivo =~ "main"
  end

  # RN-787 (AT-464): a tarefa B nasce da A (RN-760); a A é mergeada na `main` da
  # ORIGEM e a `main` local do clone fica para trás. O diff da PR de B é só B.
  test "RN-787: o diff é contra a `main` da origem, não a `main` local parada", %{root: root} do
    project_id = Ecto.UUID.generate()
    insert_repo!(project_id)
    origem = Path.join(root, "origem.git")
    git!(root, ["init", "--bare", "--initial-branch=main", origem])
    seed = Path.join(root, "seed")
    git!(root, ["clone", "-q", origem, seed])
    commit!(seed, "README.md", "base")
    git!(seed, ["push", "-q", "origin", "HEAD:main"])

    wt = Path.join(root, "wt")
    git!(root, ["clone", "-q", origem, wt])
    git!(wt, ["checkout", "-q", "-b", "feature/a"])
    commit!(wt, "A.md", "a")
    git!(wt, ["push", "-q", "origin", "feature/a"])

    git!(seed, ["fetch", "-q", "origin"])
    git!(seed, ["merge", "-q", "origin/feature/a"])
    git!(seed, ["push", "-q", "origin", "HEAD:main"])

    git!(wt, ["checkout", "-q", "-b", "feature/b"])
    commit!(wt, "B.md", "b")

    assert {:ok, diff} = Diff.compute(project_id, wt)
    assert Diff.changed_paths(diff) == ["B.md"]
  end

  test "projeto sem repositório continua `{:error, :not_found}`", %{root: root} do
    assert {:error, :not_found} = Diff.compute(Ecto.UUID.generate(), root)
  end

  test "o contexto do projeto diz a branch de TRABALHO, não a default" do
    project_id = Ecto.UUID.generate()
    insert_repo!(project_id)

    assert ProjectContext.build(project_id) =~ "Repositório · branch de trabalho main"
    refute ProjectContext.build(project_id) =~ "branch dev"
  end
end
