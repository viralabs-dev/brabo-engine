defmodule Engine.Harness.Tools.UpdateTask do
  @moduledoc """
  Ferramenta do PO e do Dev Lead (RN-1068, AT-805): CORRIGE o título e/ou a
  descrição de uma tarefa `todo`, para que ela deixe de contradizer uma
  decisão tomada depois. O `task_id` aceita o prefixo (RN-721) e é resolvido
  para o uuid antes da chamada. A recusa da api (409 nomeado:
  `tarefa_em_execucao`, `historia_arquivada`, `historia_nao_draft`) volta ao
  modelo com o motivo, como em `update_story`. `:direct`.
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Harness.IdDoBacklog
  alias Engine.Harness.Tools.RecusaDeHistoria
  alias Engine.Sessions.EngineApiClient

  @impl true
  def spec do
    %{
      name: "update_task",
      description:
        "Corrige o TÍTULO e/ou a DESCRIÇÃO de uma tarefa existente (só `todo`). Use quando a " <>
          "tarefa contradiz uma decisão tomada depois, em vez de deixar um recado. Tarefa já " <>
          "em execução é recusada. Campo omitido fica como está.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "task_id" => %{"type" => "string"},
          "title" => %{"type" => "string"},
          "description" => %{"type" => "string"},
          "question_id" => %{
            "type" => "string",
            "description" =>
              "questionId da pergunta em aberto JÁ respondida que motiva a correção " <>
                "(destrava tarefa de história ready)"
          }
        },
        "required" => ["task_id"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(%{"task_id" => task_id} = args, ctx) when is_binary(task_id) do
    fields =
      %{
        title: Map.get(args, "title"),
        description: Map.get(args, "description"),
        questionId: Map.get(args, "question_id"),
        agentId: if(Map.get(ctx, :agent) == "dev-lead", do: "dev-lead", else: "po")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if Map.take(fields, [:title, :description]) == %{} do
      {:error, "update_task exige `title` ou `description`"}
    else
      with {:ok, task_id} <- IdDoBacklog.resolver(ctx.project_id, :tarefa, task_id) do
        case EngineApiClient.update_task(ctx.project_id, ctx.session_id, task_id, fields) do
          {:ok, %{"id" => id} = task} ->
            {:ok, "tarefa corrigida: id=#{id}, título=\"#{Map.get(task, "title")}\"."}

          {:error, reason} ->
            {:error, "falha ao corrigir tarefa: #{RecusaDeHistoria.texto(reason)}"}
        end
      end
    end
  end

  def run(_args, _ctx), do: {:error, "update_task exige `task_id`"}
end
