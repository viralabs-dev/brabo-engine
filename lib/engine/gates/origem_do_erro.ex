defmodule Engine.Gates.OrigemDoErro do
  @moduledoc """
  Origem (RN-059) do erro de LLM que parou o turno de um gate (RN-897, AT-586).
  Provider que CORTA a chamada de ferramenta no teto de saída ("Tool calls
  cutoff by max_tokens") é o modelo estourando o teto, não a infra caindo;
  a "falha repetida de ferramenta" (RN-913) é o laço do próprio agente de QA
  (AT-984); qualquer outro erro de LLM segue `infra`.
  """

  alias Engine.Agents.FalhaDeTurno

  @spec de_llm(term()) :: String.t()
  def de_llm(error) do
    texto = to_string(error)

    if String.contains?(texto, "cutoff by max_tokens") or
         String.contains?(texto, "falha repetida de ferramenta"),
       do: "modelo",
       else: "infra"
  end

  @doc """
  AT-984 (RN-1347): o bloqueio de gate é falha PASSAGEIRA do provedor? Só
  `infra` conta, e o texto do diagnóstico é a única fonte (o subagente não
  repassa o `errorCode`): rede/5xx/429 da RN-864, mais o "Connection error."
  que o provedor devolve sem código. Crédito esgotado nunca é passageira.
  """
  @spec passageira?(term()) :: boolean()
  def passageira?(%{origin: "infra", diagnosis: diagnosis}) when is_binary(diagnosis) do
    FalhaDeTurno.passageira?(diagnosis) or
      (not FalhaDeTurno.credito_esgotado?(diagnosis) and
         diagnosis =~ ~r/connection error|timed? ?out/i)
  end

  def passageira?(_), do: false
end
