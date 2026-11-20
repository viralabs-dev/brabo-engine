defmodule Engine.Infra.Tools.ProposeContainerStop do
  @moduledoc """
  Spec da ferramenta `propose_container_stop` — pro modelo do Infra Lead
  (AT-980, RN-1363). `Engine.Infra.InfraLeadServer` a intercepta e propõe
  `container_stop` pela api, com a recusa local por modo (RN-1364); `run/2` é só
  salvaguarda de behaviour e nunca deveria ser chamado.
  """

  @behaviour Engine.Harness.Tool

  @impl true
  def spec do
    %{
      name: "propose_container_stop",
      description:
        "Propõe PARAR o container do projeto (`container_stop`), sem apagá-lo. Só para `container`/`mounted` (o broker); `runner` ainda não é atendido (runner depois). A decisão é do usuário.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "rationale" => %{
            "type" => "string",
            "description" => "Por que agora (opcional) — texto livre, sem mínimo."
          }
        },
        "required" => []
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(_args, _ctx),
    do:
      {:error,
       "propose_container_stop é interceptada pelo InfraLeadServer antes de chegar " <>
         "aqui — run/2 nunca deveria ser invocado"}
end
