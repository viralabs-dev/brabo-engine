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

  test "dispara na última tarefa do projeto (campo da api), nunca por história" do
    assert CloneLimpo.disparar?(["src/a.ts"], %{ultima_do_projeto: true})
    refute CloneLimpo.disparar?(["src/a.ts"], %{ultima_do_projeto: false})
    # sem o campo (api antiga), nem a história toda `done` dispara
    refute CloneLimpo.disparar?(["src/a.ts"], %{sibling_tasks: [%{"status" => "done"}]})
  end

  test "com a raiz do projeto, o clone também sai onde o broker procura, com .env e fora do git",
       %{dir: dir} do
    File.write!(Path.join(dir, ".env.example"), "PORT=3000\n")
    git!(dir, ["add", ".env.example"])
    git!(dir, ["commit", "-q", "-m", "env"])

    raiz = tmp!()
    git!(raiz, ["init", "-q"])

    assert {:ok, ".brabo-qa/clone-limpo"} = CloneLimpo.preparar(dir, raiz)

    for base <- [dir, raiz] do
      clone = Path.join(base, ".brabo-qa/clone-limpo")
      assert File.exists?(Path.join(clone, "src/a.ts"))
      assert File.read!(Path.join(clone, ".env")) == "PORT=3000\n"
    end

    assert File.read!(Path.join(raiz, ".git/info/exclude")) =~ ".brabo-qa/"
    # idempotente: o exclude não duplica
    assert {:ok, _} = CloneLimpo.preparar(dir, raiz)
    exclude = File.read!(Path.join(raiz, ".git/info/exclude"))
    assert length(String.split(exclude, ".brabo-qa/")) == 2
  end

  test "o .env que o clone já tem não é sobrescrito", %{dir: dir} do
    File.write!(Path.join(dir, ".env.example"), "A=1\n")
    File.write!(Path.join(dir, ".env"), "A=versionado\n")
    git!(dir, ["add", "-f", ".env.example", ".env"])
    git!(dir, ["commit", "-q", "-m", "env"])

    assert {:ok, _} = CloneLimpo.preparar(dir)
    assert File.read!(Path.join(dir, ".brabo-qa/clone-limpo/.env")) == "A=versionado\n"
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
