defmodule Engine.Dev.AvancarPastaRunnerTest do
  @moduledoc """
  RN-1027 (AT-617): o avanço da pasta do projeto `runner`, pelo `exec` do canal.
  O runner é falso e responde ao git por roteiro; o que se prova é QUAIS comandos
  o engine manda e que recusa nomeia, nunca o git em si (esse é o do caminho local).
  """
  use Engine.DataCase, async: false
  use Oban.Testing, repo: Engine.Repo, prefix: "engine"

  alias Engine.Dev.WorktreeManager
  alias Engine.Runners.Registry

  defp insert_runner_project!(id) do
    Repo.query!(
      "INSERT INTO public.projects " <>
        "(id, name, slug, workspace_dir_name, execution_mode, workspace_path, workspace_verified_at) " <>
        "VALUES ($1, 'proj', 'proj', 'exp-avanco1', 'runner', '/home/u/proj', now())",
      [Ecto.UUID.dump!(id)]
    )

    Repo.query!(
      "INSERT INTO public.project_repositories " <>
        "(id, project_id, provider, external_id, url, default_branch, visibility, provisioned_by) " <>
        "VALUES ($1, $2, 'local', '/tmp/x.git', 'file:///tmp/x.git', 'main', 'private', $3)",
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        Ecto.UUID.dump!(id),
        Ecto.UUID.dump!(Ecto.UUID.generate())
      ]
    )

    container_running!(id)
  end

  # Runner falso com roteiro. `opts`: branch, sujo, ancestral (exit do merge-base),
  # fetch (exit), merge (exit do `merge --ff-only`), ja_em_dia, pronto.
  defp start_runner!(project_id, opts) do
    parent = self()

    pid =
      spawn(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Engine.Repo, parent, self())
        :ok = Registry.register(project_id, self())
        send(parent, :runner_pronto)
        loop(parent, opts, false)
      end)

    assert_receive :runner_pronto, 1_000
    on_exit(fn -> Process.exit(pid, :kill) end)
  end

  defp loop(parent, opts, merged) do
    receive do
      {:dispatch_exec, ref, cmd, _cwd, _env, _cred, from, _t} ->
        send(parent, {:cmd, cmd})
        {code, out} = responder(cmd, opts, merged)

        send(
          from,
          {:runner_exec_result, ref, %{"exitCode" => code, "output" => out, "timedOut" => false}}
        )

        loop(parent, opts, merged or (String.contains?(cmd, "'merge' '--ff") and code == 0))
    end
  end

  defp responder("test -f " <> _, opts, _), do: {if(opts[:pronto] == false, do: 1, else: 0), ""}
  defp responder("git fetch" <> _, opts, _), do: {opts[:fetch] || 0, "fetch: #{opts[:fetch]}"}
  defp responder("git 'symbolic-ref'" <> _, opts, _), do: {0, (opts[:branch] || "main") <> "\n"}
  defp responder("git 'status'" <> _, opts, _), do: {0, opts[:sujo] || ""}
  defp responder("git 'merge-base'" <> _, opts, _), do: {opts[:ancestral] || 0, ""}
  defp responder("git 'merge'" <> _, opts, _), do: {opts[:merge] || 0, "would be overwritten"}

  defp responder("git 'rev-parse' '--verify'" <> _, _, _), do: {0, ""}

  defp responder("git 'rev-parse' 'HEAD'", opts, merged),
    do: {0, if(merged or opts[:ja_em_dia], do: "bbb\n", else: "aaa\n")}

  defp responder("git 'rev-parse' 'origin/main'", _, _), do: {0, "bbb\n"}
  defp responder(_, _, _), do: {0, ""}

  defp comandos(acc \\ []) do
    receive do
      {:cmd, c} -> comandos([c | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp avancar(opts) do
    id = Ecto.UUID.generate()
    insert_runner_project!(id)
    start_runner!(id, opts)
    {WorktreeManager.avancar_pasta(id), comandos()}
  end

  test "pasta atrás da main avança: manda o merge --ff-only e devolve de/para" do
    assert {{:avancou, "aaa", "bbb"}, cmds} = avancar([])
    assert "git 'merge' '--ff-only' 'origin/main'" in cmds
  end

  test "já em dia: nenhum merge" do
    assert {:em_dia, cmds} = elem_resultado(avancar(ja_em_dia: true))
    refute Enum.any?(cmds, &String.contains?(&1, "'merge' '--ff"))
  end

  test "outra branch: other_branch, sem merge" do
    assert {{:recusado, :other_branch, "feature/x"}, cmds} = avancar(branch: "feature/x")
    refute Enum.any?(cmds, &String.contains?(&1, "'merge' '--ff"))
  end

  test "árvore suja: dirty_tree, sem merge" do
    assert {{:recusado, :dirty_tree, "main"}, cmds} = avancar(sujo: " M a.txt\n")
    refute Enum.any?(cmds, &String.contains?(&1, "'merge' '--ff"))
  end

  test "main divergida: diverged, sem merge" do
    assert {{:recusado, :diverged, "main"}, cmds} = avancar(ancestral: 1)
    refute Enum.any?(cmds, &String.contains?(&1, "'merge' '--ff"))
  end

  test "não rastreado que seria sobrescrito: untracked_conflict com a saída" do
    assert {{:recusado, {:untracked_conflict, saida}, "main"}, _} = avancar(merge: 1)
    assert saida =~ "would be overwritten"
  end

  test "fetch que falha: fetch_failed, nenhuma decisão tomada" do
    assert {{:recusado, {:fetch_failed, _}, nil}, cmds} = avancar(fetch: 128)
    refute Enum.any?(cmds, &String.contains?(&1, "'status'"))
  end

  test "pasta sem a marca de pronto: noop, sem fetch" do
    assert {:noop, cmds} = elem_resultado(avancar(pronto: false))
    refute Enum.any?(cmds, &String.starts_with?(&1, "git fetch"))
  end

  test "sem runner conectado: runner_offline, sem exceção" do
    id = Ecto.UUID.generate()
    insert_runner_project!(id)
    assert {:recusado, :runner_offline, nil} = WorktreeManager.avancar_pasta(id)
  end

  defp elem_resultado({r, c}), do: {r, c}

  describe "decidir_avanco/1 (a decisão pura, sobre qualquer transporte)" do
    defp git_fake(respostas) do
      fn args -> Map.get(respostas, hd(args), fn _ -> {:ok, ""} end).(args) end
    end

    test "a mesma função decide para um transporte qualquer" do
      git =
        git_fake(%{
          "symbolic-ref" => fn _ -> {:ok, "main\n"} end,
          "status" => fn _ -> {:ok, " M x\n"} end
        })

      assert {:recusado, :dirty_tree, "main"} = WorktreeManager.decidir_avanco(git)
    end

    test "sem origin/main: noop" do
      git = git_fake(%{"rev-parse" => fn _ -> {:error, ""} end})
      assert :noop = WorktreeManager.decidir_avanco(git)
    end
  end
end
