defmodule Engine.Gates.CloneLimpoTest do
  # AT-921 (RN-1121): a corrente com git de verdade.
  use ExUnit.Case, async: true

  alias Engine.Gates.{CloneLimpo, RecorteDaTarefa}

  defp git!(dir, args), do: {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)

  defp tmp! do
    dir = Path.join(System.tmp_dir!(), "clone-limpo-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  setup do
    dir = tmp!()
    git!(dir, ["init", "-q"])
    git!(dir, ["config", "user.email", "t@t"])
    git!(dir, ["config", "user.name", "t"])
    File.mkdir_p!(Path.join(dir, "src"))
    File.write!(Path.join(dir, "package.json"), "{}")
    File.write!(Path.join(dir, "src/a.ts"), "a")
    git!(dir, ["add", "."])
    git!(dir, ["commit", "-q", "-m", "um"])
    %{dir: dir}
  end

  test "dispara com manifesto ou build, não com só src/" do
    assert CloneLimpo.disparar?(["modules/api/package.json"], %{})
    assert CloneLimpo.disparar?(["Dockerfile.dev"], %{})
    assert CloneLimpo.disparar?(["pnpm-lock.yaml"], %{})
    refute CloneLimpo.disparar?(["src/a.ts"], %{})
  end

  test "dispara na última tarefa pendente" do
    todas = %{sibling_tasks: [%{"status" => "done"}], module_open_tasks: []}
    assert CloneLimpo.disparar?(["src/a.ts"], todas)
    refute CloneLimpo.disparar?(["src/a.ts"], %{todas | module_open_tasks: [%{"title" => "x"}]})
    refute CloneLimpo.disparar?(["src/a.ts"], %{sibling_tasks: [%{"status" => "todo"}]})
  end

  test "prepara só o commit: sem node_modules, sem arquivo solto, sem o tar", %{dir: dir} do
    File.mkdir_p!(Path.join(dir, "node_modules/x"))
    File.write!(Path.join(dir, "node_modules/x/i.js"), "x")
    File.write!(Path.join(dir, "solto.txt"), "não versionado")

    assert {:ok, ".brabo-qa/clone-limpo"} = CloneLimpo.preparar(dir)

    clone = Path.join(dir, ".brabo-qa/clone-limpo")
    assert File.exists?(Path.join(clone, "package.json"))
    assert File.exists?(Path.join(clone, "src/a.ts"))
    refute File.exists?(Path.join(clone, "node_modules"))
    refute File.exists?(Path.join(clone, "solto.txt"))
    refute File.exists?(clone <> ".tar")

    # refeito do HEAD novo, sem sobrar o anterior
    File.write!(Path.join(dir, "src/b.ts"), "b")
    git!(dir, ["add", "."])
    git!(dir, ["commit", "-q", "-m", "dois"])
    assert {:ok, _} = CloneLimpo.preparar(dir)
    assert File.exists?(Path.join(clone, "src/b.ts"))
  end

  test "o recorte traz a seção só com o clone", %{dir: dir} do
    {:ok, pasta} = CloneLimpo.preparar(dir)
    task = %{task: %{"title" => "T"}}

    assert RecorteDaTarefa.texto(Map.put(task, :clone_limpo, {:ok, pasta})) =~
             "Clone limpo (AT-921)"

    assert RecorteDaTarefa.texto(Map.put(task, :clone_limpo, {:indisponivel, "x"})) =~
             "indisponível"

    refute RecorteDaTarefa.texto(task) =~ "Clone limpo"
  end

  test "sem repositório, indisponível (e o QA não reprova por isso)" do
    assert {:indisponivel, _} = CloneLimpo.preparar(tmp!())
  end
end
