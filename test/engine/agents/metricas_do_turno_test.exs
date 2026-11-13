defmodule Engine.Agents.MetricasDoTurnoTest do
  # RN-1158..1161 (AT-933): o fecho do turno leva o que gravou, o custo, as
  # chamadas, o raciocínio e a duração como CAMPOS.
  use ExUnit.Case, async: true

  alias Engine.Agents.{GravadoNoTurno, MetricasDoTurno, TextoDoTurno}
  alias Engine.Harness.IdiomaDaResposta

  test "RN-1159: soma custo, chamadas e raciocínio das chamadas; duração do turno" do
    MetricasDoTurno.registrar(%{"usage" => %{"costMicros" => 100, "reasoningTokens" => 30}})
    MetricasDoTurno.registrar(%{"usage" => %{"costMicros" => 50, "latencyMs" => 5}})

    assert %{custoMicros: 150, chamadasLlm: 2, raciocinioTokens: 30, duracaoMs: d} =
             MetricasDoTurno.descarregar()

    assert d >= 0
    assert MetricasDoTurno.descarregar() == %{}
  end

  test "RN-1159: sem reasoningTokens no usage o campo não existe" do
    MetricasDoTurno.registrar(%{"usage" => %{"estimated" => true}})
    m = MetricasDoTurno.descarregar()
    assert %{custoMicros: 0, chamadasLlm: 1} = m
    refute Map.has_key?(m, :raciocinioTokens)
  end

  test "RN-1158/1160: o fecho traz gravadoNoTurno como campo e o texto continua igual" do
    for _ <- 1..2,
        do: GravadoNoTurno.anotar("emit_artifact", %{"type" => "business_rule"}, {:ok, 1})

    GravadoNoTurno.anotar("propose_adr", %{}, {:error, "x"})
    MetricasDoTurno.registrar(%{"usage" => %{"costMicros" => 7}})

    p =
      IdiomaDaResposta.com_idioma_do_autor("pt-BR", fn ->
        TextoDoTurno.payload_do_turno("Feito.", "m")
      end)

    assert p.content =~ "Gravado neste turno: 2 regras de negócio; 1 chamada de escrita recusada."
    assert p.gravadoNoTurno == %{itens: [%{tipo: "regra", total: 2}], recusadas: 1}
    assert %{custoMicros: 7, chamadasLlm: 1} = Map.take(p, [:custoMicros, :chamadasLlm])
  end

  test "RN-1161: turno sem escrita e sem chamada não ganha campos" do
    p = TextoDoTurno.payload_do_turno("Oi.", "m")
    refute Map.has_key?(p, :gravadoNoTurno)
    refute Map.has_key?(p, :custoMicros)
  end
end
