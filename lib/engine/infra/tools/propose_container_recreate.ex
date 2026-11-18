defmodule Engine.Infra.Tools.ProposeContainerRecreate do
  @moduledoc """
  Spec da ferramenta `propose_container_recreate` — pro modelo do Infra Lead
  (AT-980, RN-1363). `Engine.Infra.InfraLeadServer` a intercepta e propõe
  `container_recreate` pela api, com a recusa local por modo (RN-1364); `run/2` é só
  salvaguarda de behaviour e nunca deveria ser chamado.
  """

  @behaviour Engine.Harness.Tool

  @impl true
  def spec do
    %{
      name: "propose_container_recreate",
      description:
        "Propõe RECRIAR o container do projeto (`container_recreate`: remove + start com a spec vigente de comando, rede e portas). Use quando o container parado tem spec antiga — `propose_container_start` o religaria como está. Só para `container`/`mounted`; nasce sempre `pending` (RN-934): o clique é humano.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "ports" => %{
            "type" => "array",
            "description" =>
              "Portas a publicar (opcional), cada uma {host, container, protocol}.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "host" => %{"type" => "integer"},
                "container" => %{"type" => "integer"},
                "protocol" => %{"type" => "string", "enum" => ["tcp", "udp"]}
              },
              "required" => ["host", "container"]
            }
          },
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
       "propose_container_recreate é interceptada pelo InfraLeadServer antes de chegar " <>
         "aqui — run/2 nunca deveria ser invocado"}
end
