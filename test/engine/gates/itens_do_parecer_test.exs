defmodule Engine.Gates.ItensDoParecerTest do
  # AT-905 (RN-1116..1118)
  use ExUnit.Case, async: true

  alias Engine.Gates.ItensDoParecer

  @anterior %{itens: ["x"]}
  defp parecer(itens), do: %{veredito: "changes_requested", resumo: "r", itens: itens}

  test "string e {texto, origem} viram texto" do
    assert ItensDoParecer.textos(["a", %{"texto" => "b", "origem" => "anterior"}]) == ["a", "b"]
  end

  test "primeira volta (sem pedido anterior) não confere nada" do
    p =
      ItensDoParecer.aplicar(
        parecer([%{"texto" => "z", "origem" => "regressao_no_diff"}]),
        nil,
        nil
      )

    assert p.itens == ["z"]
    assert p.veredito == "changes_requested"
  end

  test "regressao_no_diff sem arquivo do diff vai para melhorias; o resto fica" do
    p =
      ItensDoParecer.aplicar(
        parecer([
          %{"texto" => "ideia solta", "origem" => "regressao_no_diff"},
          %{"texto" => "src/b.ts quebrou", "origem" => "regressao_no_diff"},
          %{"texto" => "pedido antigo", "origem" => "anterior"}
        ]),
        @anterior,
        ["src/b.ts"]
      )

    assert p.itens == ["src/b.ts quebrou", "pedido antigo"]
    assert [m] = p.melhorias
    assert m =~ "ideia solta"
    assert m =~ "RN-1118"
    assert p.veredito == "changes_requested"
  end

  test "tudo movido: o parecer deixa de reprovar" do
    p =
      ItensDoParecer.aplicar(
        parecer([%{"texto" => "ideia", "origem" => "regressao_no_diff"}]),
        @anterior,
        []
      )

    assert p.veredito == "approved"
    assert p.itens == []
  end
end
