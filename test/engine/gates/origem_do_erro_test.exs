defmodule Engine.Gates.OrigemDoErroTest do
  use ExUnit.Case, async: true

  alias Engine.Gates.OrigemDoErro

  test "corte por max_tokens é do modelo (RN-897)" do
    assert OrigemDoErro.de_llm("Tool calls cutoff by max_tokens (BaseTen 502)") == "modelo"
  end

  test "outro erro de provider segue infra" do
    assert OrigemDoErro.de_llm("timeout de 120s") == "infra"
  end

  test "falha repetida de ferramenta é o laço do próprio QA: modelo (AT-984)" do
    assert OrigemDoErro.de_llm("falha repetida de ferramenta") == "modelo"
  end

  test "passageira?: só infra, só rede/5xx/429/Connection error, nunca crédito (AT-984)" do
    infra = fn d -> %{origin: "infra", diagnosis: d} end

    assert OrigemDoErro.passageira?(infra.("falha no turno de LLM: \"Connection error.\""))
    assert OrigemDoErro.passageira?(infra.("falha no turno de LLM: \"getaddrinfo EAI_AGAIN x\""))
    assert OrigemDoErro.passageira?(infra.("openrouter respondeu com status 503"))
    refute OrigemDoErro.passageira?(infra.("openrouter respondeu com status 402: credits"))
    refute OrigemDoErro.passageira?(infra.("broker recusou"))
    refute OrigemDoErro.passageira?(%{origin: "modelo", diagnosis: "Connection error."})
  end
end
