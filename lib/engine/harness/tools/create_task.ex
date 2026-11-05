defmodule Engine.Harness.Tools.CreateTask do
  @moduledoc """
  Ferramenta do PO: cria uma tarefa sob uma história via a api. A tarefa herda
  o vínculo a regra da história. `:direct`, fora do `@registry` global.
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Harness.IdDoBacklog
  alias Engine.Sessions.EngineApiClient

  @impl true
  def spec do
    %{
      name: "create_task",
      description: "Cria uma tarefa sob uma história (story_id).",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "story_id" => %{"type" => "string"},
          "title" => %{"type" => "string"},
          "description" => %{"type" => "string"}
        },
        "required" => ["story_id", "title"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(%{"story_id" => story_id, "title" => title} = args, ctx) do
    # RN-721: aceita o prefixo (>= 8 hex) que o modelo copia encurtado.
    with {:ok, story_id} <- IdDoBacklog.resolver(ctx.project_id, :historia, story_id) do
      fields =
        %{storyId: story_id, title: title, description: Map.get(args, "description", "")}
        |> put_agent_role(Map.get(ctx, :agent_role))

      case EngineApiClient.create_task(ctx.project_id, ctx.session_id, fields) do
        {:ok, %{"id" => id}} -> {:ok, "tarefa criada: id=#{id}."}
        {:error, reason} -> {:error, "falha ao criar tarefa: #{inspect(reason)}"}
      end
    end
  end

  def run(_args, _ctx), do: {:error, "create_task exige `story_id` e `title`"}

  # RN-1006: só o Dev Lead diz quem criou; sem o campo a api assume o PO.
  defp put_agent_role(fields, nil), do: fields
  defp put_agent_role(fields, role), do: Map.put(fields, :agentRole, role)
end
