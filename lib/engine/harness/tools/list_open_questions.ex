defmodule Engine.Harness.Tools.ListOpenQuestions do
  @moduledoc """
  Lista TODAS as perguntas em aberto do projeto, de qualquer autor (AT-804,
  RN-874). O texto do turno (`DecisoesDoProjeto`) tem teto e pode deixar
  perguntas de fora; é esta ferramenta que fecha a conta antes de o agente
  fechar "todas". Leitura LOCAL do event log, sem HTTP.

  Ferramenta do Criativo, do PO, do Arquiteto e do Dev Lead.
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Harness.DecisoesDoProjeto
  alias Engine.SessionEvents.Event

  @limite 50

  @impl true
  def spec do
    %{
      name: "list_open_questions",
      description:
        "Lista TODAS as perguntas em aberto do projeto, de qualquer autor, com `questionId`, " <>
          "autor e sugestão. Use antes de fechar \"todas\" as perguntas: " <>
          "`answer_open_question` fecha pergunta de qualquer autor.",
      parameters: %{"type" => "object", "properties" => %{}}
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(_args, ctx) do
    eventos =
      Event.list_types_for_project(
        ctx.project_id,
        ["artifact.open_question", "open_question.answered"],
        200
      )

    case DecisoesDoProjeto.abertas(eventos) do
      [] ->
        {:ok, "nenhuma pergunta aberta"}

      todas ->
        linhas =
          for a <- Enum.take(todas, @limite) do
            DecisoesDoProjeto.linha_aberta(a) <> " [autor: #{a.autor}]"
          end

        {:ok, Enum.join(linhas, "\n") <> "\ntotal: #{length(todas)}"}
    end
  end
end
