defmodule Engine.Dev.MemoriaExtratorTest do
  @moduledoc """
  RN-1112, RN-1113, RN-1114 (AT-923, ADR 0293): o cartão do módulo sai do
  código, sem LLM; a seção humana só muda pelo `como_usar`; a divergência
  contrato × código é dita nos dois sentidos.
  """

  use ExUnit.Case, async: true

  alias Engine.Dev.MemoriaExtrator

  setup do
    dir = Path.join(System.tmp_dir!(), "brabo-mem-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp escreve!(dir, rel, texto) do
    abs = Path.join(dir, rel)
    File.mkdir_p!(Path.dirname(abs))
    File.write!(abs, texto)
  end

  defp projeto_ts!(dir) do
    escreve!(dir, "package.json", """
    {"name":"@x/api","main":"dist/index.js",
     "scripts":{"test":"vitest","start":"node dist/main.js"},
     "dependencies":{"@x/db":"workspace:*","express":"^4"}}
    """)

    escreve!(dir, "tsconfig.json", "{}")

    escreve!(dir, "src/index.ts", """
    export function criar(a: number) {}
    export const VERSAO = 1;
    export interface Item {}
    export { listar, remover as apagar } from './repo';
    export * from './rotas.js';
    """)

    escreve!(dir, "src/repo.ts", "export function listar() {}\nexport function remover() {}\n")

    escreve!(dir, "src/rotas.ts", """
    export function montar() {}
    app.get('/itens/:id', h);
    router.post("/itens", h);
    """)

    escreve!(dir, "src/rotas.test.ts", "app.get('/de-teste', h);")
    escreve!(dir, "node_modules/x/index.js", "export function lixo() {}")
    escreve!(dir, "migrations/001_init.sql", "create table t();")
    escreve!(dir, "openapi.json", ~s({"paths":{"/saude":{"get":{}}}}))
  end

  defp le(dir, modulo \\ "api"),
    do: File.read!(Path.join(dir, ".brabo/memoria/modulos/#{modulo}.md"))

  test "TS/Node: exports, export *, rotas, openapi, scripts, migrações e dependência irmã", %{
    dir: dir
  } do
    projeto_ts!(dir)
    assert {:ok, ".brabo/memoria/modulos/api.md"} = MemoriaExtrator.escrever(dir, "api")
    card = le(dir)

    assert card =~ "modulo: api\nstack: node-ts\ndepende_de: [@x/db]"
    assert card =~ "Ponto de entrada: `src/index.ts`"
    assert card =~ "`criar` (função)"
    assert card =~ "`VERSAO` (valor)"
    assert card =~ "`Item` (tipo)"
    assert card =~ "`apagar` (export)"
    assert card =~ "`montar` (função)"
    assert card =~ "`GET /itens/:id` (rota)"
    assert card =~ "`POST /itens` (rota)"
    assert card =~ "`GET /saude` (rota)"
    refute card =~ "/de-teste"
    refute card =~ "lixo"
    assert card =~ "- `test`: `vitest`"
    assert card =~ "- `migrations/001_init.sql`"
    assert card =~ "ainda não escrito pelo dev do módulo"
    assert card =~ "<!-- brabo:gerado -->"
  end

  test "idempotente: o mesmo código gera o mesmo arquivo", %{dir: dir} do
    projeto_ts!(dir)
    MemoriaExtrator.escrever(dir, "api")
    primeiro = le(dir)
    MemoriaExtrator.escrever(dir, "api")
    assert le(dir) == primeiro
  end

  test "como_usar troca só a seção humana; a gerada é sobrescrita", %{dir: dir} do
    projeto_ts!(dir)
    MemoriaExtrator.escrever(dir, "api", como_usar: "Rode `npm start`.")
    assert le(dir) =~ "## Como usar\n\nRode `npm start`."

    # sem como_usar, o texto do dev fica
    escreve!(dir, "src/novo.ts", "export function novo() {}")

    escreve!(
      dir,
      "src/index.ts",
      File.read!(Path.join(dir, "src/index.ts")) <> "export * from './novo';\n"
    )

    MemoriaExtrator.escrever(dir, "api")
    assert le(dir) =~ "Rode `npm start`."
    assert le(dir) =~ "`novo` (função)"

    MemoriaExtrator.escrever(dir, "api", como_usar: "Outro texto")
    card = le(dir)
    assert card =~ "## Como usar\n\nOutro texto"
    refute card =~ "Rode `npm start`."
  end

  test "RN-1114: o contrato vem renderizado e a divergência é dita nos dois sentidos", %{dir: dir} do
    projeto_ts!(dir)

    contrato = %{
      "modulo" => "api",
      "dependeDe" => ["db"],
      "expoe" => [
        %{"tipo" => "funcao", "assinatura" => "criar(a)", "descricao" => "cria"},
        %{"tipo" => "funcao", "assinatura" => "sumir()"},
        %{"tipo" => "rota", "assinatura" => "GET /itens/{id}"},
        %{"tipo" => "rota", "assinatura" => "DELETE /itens/{id}"}
      ]
    }

    MemoriaExtrator.escrever(dir, "api", contrato: contrato, versao: 3)
    card = le(dir)

    assert card =~ "depende_de: [db, @x/db]"
    assert card =~ "## Contrato declarado (v3)"
    assert card =~ "- [funcao] criar(a) — cria"
    assert card =~ "`sumir()` está no contrato e não existe no código"
    assert card =~ "`DELETE /itens/{id}` está no contrato e o código não serve"
    assert card =~ "`montar` o código exporta e o contrato não declara"
    assert card =~ "`POST /itens` o código serve e o contrato não declara"
    refute card =~ "`criar()` está no contrato"
    refute card =~ "`GET /itens/:id` o código serve e o contrato não declara"
  end

  test "linguagem desconhecida: só a lista de arquivos e a seção humana", %{dir: dir} do
    escreve!(dir, "main.py", "def f(): pass")
    MemoriaExtrator.escrever(dir, "py")
    card = le(dir, "py")
    assert card =~ "stack: desconhecida"
    assert card =~ "- `main.py`"
    assert card =~ "## Como usar"
  end

  test "o ponteiro no AGENTS.md da raiz entra uma vez só; pasta fora do alcance é ignorada", %{
    dir: dir
  } do
    escreve!(dir, "AGENTS.md", "# Regras")
    MemoriaExtrator.escrever(dir, "a")
    MemoriaExtrator.escrever(dir, "a")
    agentes = File.read!(Path.join(dir, "AGENTS.md"))
    assert agentes =~ "# Regras"
    assert length(String.split(agentes, ".brabo/memoria/")) == 2

    assert MemoriaExtrator.escrever(nil, "a") == :ignorado
    assert MemoriaExtrator.escrever(Path.join(dir, "nao-existe"), "a") == :ignorado
  end

  test "o módulo com pasta própria usa a pasta; o cartão vai para a raiz do worktree", %{dir: dir} do
    escreve!(dir, "api/package.json", ~s({"name":"api"}))
    escreve!(dir, "api/index.js", "module.exports = { alfa, beta: 1 }\nexports.gama = 2\n")
    MemoriaExtrator.escrever(dir, "api")
    card = le(dir)
    assert card =~ "stack: node\n"
    assert card =~ "`alfa` (export)"
    assert card =~ "`beta` (export)"
    assert card =~ "`gama` (export)"
  end
end
