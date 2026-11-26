defmodule Engine.Gates.TestesSemProvaTest do
  # AT-1023 (RN-1513)
  use ExUnit.Case, async: true

  alias Engine.Gates.TestesSemProva

  @cedo """
  const pgTeste = process.env.DATABASE_URL_TESTE;
  it('cria o admin', async () => {
    if (!pgTeste) return;
    expect(await criar()).toBe(1);
  });
  """

  test "marca o teste que retorna cedo por variável de ambiente" do
    assert TestesSemProva.retorna_cedo?(@cedo)

    assert TestesSemProva.retorna_cedo?(
             "it('x', () => {\n if (!process.env.DATABASE_URL_TESTE) return;\n expect(1).toBe(1);\n});"
           )
  end

  test "não marca it.skip nem teste que assere antes do return" do
    refute TestesSemProva.retorna_cedo?("const a = process.env.X;\nit.skip('x', () => {});")

    refute TestesSemProva.retorna_cedo?(
             "const a = process.env.X;\nit('x', () => {\n expect(1).toBe(1);\n if (!a) return;\n});"
           )
  end

  test "detectar lê os arquivos do worktree" do
    raiz = Path.join(System.tmp_dir!(), "tsp-#{System.unique_integer([:positive])}")
    File.mkdir_p!(raiz)
    on_exit(fn -> File.rm_rf!(raiz) end)
    File.write!(Path.join(raiz, "a.test.ts"), @cedo)
    File.write!(Path.join(raiz, "b.test.ts"), "it('ok', () => { expect(1).toBe(1); });")

    assert TestesSemProva.detectar_no_worktree(raiz) == ["a.test.ts"]
  end
end
