defmodule Engine.Harness.Tools.RetireBusinessRule do
  @moduledoc """
  Ferramenta do Criativo e do PO (RN-1020): RETIRA uma regra de negócio
  obsoleta. Quem valida e grava `artifact.business_rule_retired` é a api
  (RN-1018); aqui só se monta o corpo e se devolve a recusa nomeada ao modelo.
  `:direct`.
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Harness.Tools.RecusaDeHistoria
  alias Engine.Sessions.EngineApiClient

  @impl true
  def spec do
    %{
      name: "retire_business_rule",
      description:
        "Retira uma regra de negócio que ficou OBSOLETA. Você mesmo a retira, sem pedir ao " <>
          "usuário nem ao condutor, mas SEMPRE citando de onde vem a decisão: `replaced_by` " <>
          "(id da regra vigente que a substitui) e/ou `question_id` (pergunta em aberto que o " <>
          "usuário JÁ respondeu). Sem uma das duas a api recusa. As histórias que citam a " <>
          "regra passam a citar a substituta; a api recusa se uma ficaria sem regra ou tem " <>
          "tarefa em execução.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "rule_id" => %{"type" => "string", "description" => "id da regra a retirar"},
          "reason" => %{"type" => "string", "description" => "por que ela ficou obsoleta"},
          "replaced_by" => %{
            "type" => "string",
            "description" => "id da regra vigente que a substitui"
          },
          "question_id" => %{
            "type" => "string",
            "description" =>
              "questionId da pergunta em aberto JÁ respondida que motiva a retirada"
          }
        },
        "required" => ["rule_id", "reason"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(%{"rule_id" => rule_id, "reason" => reason} = args, ctx)
      when is_binary(rule_id) and is_binary(reason) do
    body =
      %{
        sessionId: ctx.session_id,
        agentRole: ctx.agent,
        reason: reason,
        replacedBy: Map.get(args, "replaced_by"),
        questionId: Map.get(args, "question_id")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    case EngineApiClient.retire_business_rule(ctx.project_id, rule_id, body) do
      {:ok, %{"ruleId" => id} = r} ->
        {:ok,
         "regra retirada: id=#{id}, substituta=#{Map.get(r, "replacedBy") || "nenhuma"}, " <>
           "histórias ajustadas=#{length(Map.get(r, "storyIds") || [])}."}

      {:error, reason} ->
        {:error, "falha ao retirar a regra: #{RecusaDeHistoria.texto(reason)}"}
    end
  end

  def run(_args, _ctx), do: {:error, "retire_business_rule exige `rule_id` e `reason`"}
end
