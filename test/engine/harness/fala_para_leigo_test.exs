defmodule Engine.Harness.FalaParaLeigoTest do
  @moduledoc "RN-1533 (AT-1026): a orientação efêmera de fala para leigo e a regra de identificador."

  use ExUnit.Case, async: true

  alias Engine.Harness.{FalaParaLeigo, FraseParaLeigo}

  @msgs [%{"role" => "user", "content" => "oi"}]

  test "anexa no fim só para os conversacionais" do
    for a <- Engine.Agents.Conversacionais.prefixos() do
      out = FalaParaLeigo.anexar(@msgs, a)
      assert List.last(out) == %{"role" => "system", "content" => FalaParaLeigo.texto()}
      assert length(out) == 2
    end

    for a <- ["dev-backend", "qa-automacao", "security", nil],
        do: assert(FalaParaLeigo.anexar(@msgs, a) == @msgs)

    assert FalaParaLeigo.texto() =~ "pelo título"
    assert FalaParaLeigo.texto() =~ "similaridade"
  end

  test "sem_identificador recusa UUID, hash e número de máquina" do
    for t <- [
          "Qual vale? (3bee9c2f-1a2b-4c3d-8e9f-0123456789ab)",
          "Parece duplicar a regra X (similaridade 0.817)",
          "acima do limiar de 0,85",
          "nota 0.817",
          "a3f9c2d41b7e0aa"
        ],
        do: assert({:error, _} = FraseParaLeigo.sem_identificador(t), t)

    for t <- [
          "Qual das duas regras vale: \"Prazo de cancelamento\" ou \"Prazo de devolução\"?",
          "Use o arquivo config.json ou o campo prazo_final?",
          "Custa R$ 10,50 por pedido? São 3 opções em 2025."
        ],
        do: assert(:ok = FraseParaLeigo.sem_identificador(t), t)
  end
end
