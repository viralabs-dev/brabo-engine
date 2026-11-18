defmodule Engine.Infra.Tools.ProposeContainerRemove do
  @moduledoc """
  Spec da ferramenta `propose_container_remove` — pro modelo do Infra Lead
  (AT-980, RN-1363). `Engine.Infra.InfraLeadServer` a intercepta e propõe
  `container_remove` pela api, com a recusa local por modo (RN-1364); `run/2` é só
  salvaguarda de behaviour e nunca deveria ser chamado.
  """

  @behaviour Engine.Harness.Tool

  @impl true
  def spec do
    %{
      name: "propose_container_remove",
      description:
        "Propõe REMOVER o container do projeto (`container_remove`). Só para `container`/`mounted`; `runner` ainda não é atendido (runner depois). Nunca é auto-aprovada: o clique é humano.",
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
       "propose_container_remove é interceptada pelo InfraLeadServer antes de chegar " <>
         "aqui — run/2 nunca deveria ser invocado"}
end
