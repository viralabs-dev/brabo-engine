defmodule Engine.Harness.Tools.PedirAInfra do
  @moduledoc """
  Ferramenta do Dev Lead: pede algo à Infra (ambiente, container, workflow) em vez de
  perguntar ao usuário (AT-996, RN-1335). Mesmo molde do `pedir_ao_arquiteto`: o pedido fica
  como `chat.message` do `dev-lead` e chega ao `InfraLeadServer` com o prefixo
  "[Pedido do Dev Lead]"; a resposta da Infra volta ao Dev Lead como aviso do sistema.
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Infra.{InfraLeadServer, InfraLeadSupervisor}
  alias Engine.Sessions.EngineApiClient

  @prefixo "[Pedido do Dev Lead] "
  @teto 2_000

  def prefixo, do: @prefixo

  @impl true
  def spec do
    %{
      name: "pedir_a_infra",
      description:
        "Pede algo à Infra (ambiente, container, app que não sobe, workflow). Diga o que " <>
          "falta e por quê. A Infra responde e você é avisado.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "mensagem" => %{
            "type" => "string",
            "description" => "O que a Infra deve fazer ou verificar (até #{@teto} caracteres)."
          }
        },
        "required" => ["mensagem"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(%{"mensagem" => mensagem}, ctx) when is_binary(mensagem) do
    texto = mensagem |> String.trim() |> String.slice(0, @teto)

    with {:vazio, false} <- {:vazio, texto == ""},
         :ok <-
           EngineApiClient.append_event(ctx.project_id, ctx.session_id, %{
             type: "chat.message",
             actorKind: "agent",
             actorId: ctx.agent,
             payload: %{"text" => @prefixo <> texto}
           }),
         {:ok, _pid, _} <- InfraLeadSupervisor.start_agent(ctx.session_id, ctx.project_id),
         resposta when resposta in [:ok] or elem(resposta, 0) == :ok <-
           InfraLeadServer.user_message(ctx.session_id, @prefixo <> texto) do
      {:ok, "pedido entregue à Infra; a resposta chega como aviso do sistema"}
    else
      {:vazio, true} -> {:error, "pedir_a_infra: `mensagem` vazia"}
      erro -> {:error, "falha ao pedir à Infra: #{inspect(erro)}"}
    end
  end

  def run(_args, _ctx), do: {:error, "pedir_a_infra exige `mensagem` (texto)"}
end
