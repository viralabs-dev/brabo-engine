defmodule Engine.Harness.Tools.PedirAoArquiteto do
  @moduledoc """
  Ferramenta do Dev Lead: pede ao Arquiteto uma interface que falta no contrato
  entre módulos (AT-748, RN-1012, ADR 0261).

  É um canal agente-para-agente que NÃO é handoff (o handoff recusa agente já
  ativo). O pedido fica como `chat.message` durável do ator `dev-lead` na sessão
  (a mesma do Arquiteto, e a `Reidratacao` lê `chat.message` de qualquer ator) e
  também chega ao Arquiteto como mensagem, com o prefixo "[Pedido do Dev Lead]".
  O aceite volta na hora; com o Arquiteto ocupado, a mensagem entra na fila dele.
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Agents.{ArquitetoServer, ArquitetoSupervisor}
  alias Engine.Sessions.EngineApiClient

  @prefixo "[Pedido do Dev Lead] "
  @teto 2_000

  @impl true
  def spec do
    %{
      name: "pedir_ao_arquiteto",
      description:
        "Pede ao Arquiteto uma interface que falta no contrato entre módulos (função, " <>
          "rota, evento ou dado de um módulo que outro precisa usar). Diga o módulo que " <>
          "precisa, o módulo dono e o que falta. O Arquiteto responde publicando um " <>
          "contrato novo; você é avisado e cria então a tarefa no módulo dono.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "pedido" => %{
            "type" => "string",
            "description" => "O que falta e por quê (até #{@teto} caracteres)."
          }
        },
        "required" => ["pedido"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(%{"pedido" => pedido}, ctx) when is_binary(pedido) do
    texto = pedido |> String.trim() |> String.slice(0, @teto)

    with {:vazio, false} <- {:vazio, texto == ""},
         :ok <-
           EngineApiClient.append_event(ctx.project_id, ctx.session_id, %{
             type: "chat.message",
             actorKind: "agent",
             actorId: ctx.agent,
             payload: %{"text" => @prefixo <> texto}
           }),
         {:ok, _pid, _} <- ArquitetoSupervisor.start_agent(ctx.session_id, ctx.project_id),
         resposta when resposta in [:ok] or elem(resposta, 0) == :ok <-
           ArquitetoServer.user_message(ctx.session_id, @prefixo <> texto) do
      {:ok, "pedido entregue ao Arquiteto; você será avisado quando o contrato novo sair"}
    else
      {:vazio, true} -> {:error, "pedir_ao_arquiteto: `pedido` vazio"}
      erro -> {:error, "falha ao pedir ao Arquiteto: #{inspect(erro)}"}
    end
  end

  def run(_args, _ctx), do: {:error, "pedir_ao_arquiteto exige `pedido` (texto)"}
end
