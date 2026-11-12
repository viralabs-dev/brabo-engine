defmodule Engine.Dev.MemoriaDoProjetoTest do
  @moduledoc """
  RN-1110 (AT-923, ADR 0293): a mensagem fixada "Memória dos módulos" traz o
  cartão do módulo, o que as dependências expõem e o contrato, dentro do
  orçamento, dizendo o que cortou.
  """

  use ExUnit.Case, async: true

  alias Engine.Dev.{MemoriaDoProjeto, MemoriaExtrator}
  alias Engine.Harness.Tokenizer

  setup do
    dir = Path.join(System.tmp_dir!(), "brabo-leitor-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp modulo!(dir, nome, expoe) do
    File.mkdir_p!(Path.join(dir, nome))

    File.write!(
      Path.join(dir, "#{nome}/package.json"),
      ~s({"name":"#{nome}","scripts":{"test":"vitest #{nome}"}})
    )

    File.write!(Path.join(dir, "#{nome}/index.js"), "exports.#{expoe} = 1\n")
  end

  defp contratos do
    [
      %{
        "modulo" => "api",
        "dependeDe" => ["db"],
        "expoe" => [%{"tipo" => "rota", "assinatura" => "GET /x"}]
      },
      %{
        "modulo" => "db",
        "dependeDe" => [],
        "expoe" => [%{"tipo" => "funcao", "assinatura" => "salvar(x)"}]
      },
      %{"modulo" => "fora", "dependeDe" => [], "expoe" => []}
    ]
  end

  test "módulo, dependência (só Expõe e Como usar) e contrato; módulo alheio fica de fora", %{
    dir: dir
  } do
    modulo!(dir, "api", "criar")
    modulo!(dir, "db", "salvar")
    modulo!(dir, "fora", "alheio")
    for m <- ~w(api db fora), do: MemoriaExtrator.escrever(dir, m, como_usar: "como usar #{m}")

    msg = MemoriaDoProjeto.mensagem(dir, "api", contratos(), 2)
    assert msg[:pinned] == true
    assert msg["role"] == "user"
    texto = msg["content"]

    assert texto =~ "Memória dos módulos"
    assert texto =~ "### Módulo `api` (o da sua tarefa)"
    assert texto =~ "`criar` (export)"
    assert texto =~ "- `test`: `vitest api`"
    assert texto =~ "como usar api"
    assert texto =~ "### Dependência `db`"
    assert texto =~ "`salvar` (export)"
    assert texto =~ "como usar db"
    # a dependência não traz Scripts, e o módulo alheio nem aparece
    refute texto =~ "vitest db"
    refute texto =~ "alheio"
    # o contrato vem do banco, com a versão
    assert texto =~ "Contrato declarado (v2)"
    assert texto =~ "[funcao] salvar(x)"
    assert Tokenizer.estimate(texto) <= MemoriaDoProjeto.orcamento_tokens()
  end

  test "cartão ausente não quebra: a mensagem diz, e o contrato ainda vem", %{dir: dir} do
    texto = MemoriaDoProjeto.mensagem(dir, "api", contratos(), 1)["content"]
    assert texto =~ "Ainda não há memória deste módulo"
    assert texto =~ "[rota] GET /x"
  end

  test "pasta que o engine não vê (runner): diz o caminho do cartão" do
    texto = MemoriaDoProjeto.mensagem(nil, "api", [], nil)["content"]
    assert texto =~ "O engine não vê a pasta do projeto"
    assert texto =~ ".brabo/memoria/modulos/api.md"
  end

  test "estouro do orçamento: o próprio é cortado na cauda e as dependências omitidas são contadas",
       %{dir: dir} do
    modulo!(dir, "api", "criar")
    modulo!(dir, "db", "salvar")
    for m <- ~w(api db), do: MemoriaExtrator.escrever(dir, m)

    gigante = String.duplicate("- `linha` (função)\n", 3_000)
    cartao = Path.join(dir, ".brabo/memoria/modulos/api.md")
    File.write!(cartao, File.read!(cartao) <> "\n## Notas\n\n" <> gigante)

    msg = MemoriaDoProjeto.mensagem(dir, "api", contratos(), 1)["content"]
    assert msg =~ "o cartão do seu módulo foi cortado na cauda"
    assert msg =~ "seção(ões) de dependências não coube(ram)"
    # ~#{8_000} de 8000, com a folga do aviso final
    assert Tokenizer.estimate(msg) <= MemoriaDoProjeto.orcamento_tokens()
  end

  test "sem o módulo no contrato, as dependências vêm do front-matter do cartão", %{dir: dir} do
    modulo!(dir, "db", "salvar")
    MemoriaExtrator.escrever(dir, "db")

    MemoriaExtrator.escrever(dir, "api",
      contrato: %{"dependeDe" => ["db"], "expoe" => []},
      versao: 1
    )

    texto = MemoriaDoProjeto.mensagem(dir, "api", [], nil)["content"]
    assert texto =~ "### Dependência `db`"
    assert texto =~ "`salvar` (export)"
  end
end
