defmodule Engine.Dev.RaizDaFundacaoTest do
  @moduledoc "RN-1415 a RN-1417 (AT-992): a raiz do workspace é da fundação e da integradora."

  use ExUnit.Case, async: true

  alias Engine.Dev.RaizDaFundacao
  alias Engine.Dev.Tools.ReportDone

  setup do
    dir = Path.join(System.tmp_dir!(), "brabo-raiz-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "apps/api"))
    on_exit(fn -> File.rm_rf!(dir) end)
    git!(dir, ["init", "-q", "-b", "main", "."])
    git!(dir, ["config", "user.email", "t@t"])
    git!(dir, ["config", "user.name", "t"])
    File.write!(Path.join(dir, "package-lock.json"), "{}\n")
    git!(dir, ["add", "-A"])
    git!(dir, ["commit", "-qm", "base"])
    %{dir: dir}
  end

  defp ctx(dir, dono?) do
    %{
      workspace_root: dir,
      dono_da_raiz: dono?,
      messages: [%{"role" => "tool", "name" => "terminal", "content" => "exit 0\nok"}]
    }
  end

  test "tarefa de módulo que altera o lock da raiz não conclui e a frase nomeia o arquivo", %{
    dir: dir
  } do
    File.write!(Path.join(dir, "package-lock.json"), "{\"x\":1}\n")
    File.write!(Path.join(dir, "apps/api/package.json"), "{}\n")

    assert {:error, frase} = ReportDone.run(%{}, ctx(dir, false))
    assert frase =~ "package-lock.json é da fundação/integradora"
    assert frase =~ "peça ao Dev Lead"
    refute frase =~ "apps/api"
  end

  test "README e compose da raiz também; arquivo de módulo passa", %{dir: dir} do
    File.write!(Path.join(dir, "README.md"), "x\n")
    File.write!(Path.join(dir, "docker-compose.yml"), "x\n")
    assert {:error, frase} = ReportDone.run(%{}, ctx(dir, false))
    assert frase =~ "README.md, docker-compose.yml"

    File.rm!(Path.join(dir, "README.md"))
    File.rm!(Path.join(dir, "docker-compose.yml"))
    File.write!(Path.join(dir, "apps/api/package.json"), "{}\n")
    assert {:ok, _} = ReportDone.run(%{}, ctx(dir, false))
  end

  test "fundação e integradora passam com a raiz alterada", %{dir: dir} do
    File.write!(Path.join(dir, "package-lock.json"), "{\"x\":1}\n")
    assert {:ok, _} = ReportDone.run(%{}, ctx(dir, true))
    assert RaizDaFundacao.dona?(%{"fundacao" => true, "title" => "Esqueleto"})

    assert RaizDaFundacao.dona?(%{
             "fundacao" => false,
             "title" => "Tarefa integradora do servidor"
           })

    refute RaizDaFundacao.dona?(%{"fundacao" => false, "title" => "Rota de pedidos"})
  end

  defp git!(dir, args), do: {_, 0} = System.cmd("git", args, cd: dir, stderr_to_stdout: true)
end
