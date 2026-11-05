defmodule Engine.Harness.Tools.AnswerOpenQuestion do
  @moduledoc """
  Fecha uma PERGUNTA EM ABERTO que o usuário já respondeu pelo chat (ADR 0214,
  RN-1003). Quem grava o fechamento é a api (o mesmo núcleo do clique em
  "Aceitar sugestão"/"Responder": `decision_record` mais
  `open_question.answered`, religando o gate); esta ferramenta só chama a rota
  interna e é idempotente (`already_answered` é sucesso).

  Ferramenta do Criativo, do PO, do Arquiteto e do Dev Lead. A descrição não
  nomeia idioma (RN-667).
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Sessions.EngineApiClient

  @teto_resposta 1000

  @impl true
  def spec do
    %{
      name: "answer_open_question",
      description:
        "Fecha uma pergunta em aberto que o usuário respondeu pelo chat, de forma INEQUÍVOCA. " <>
          "`questionId` vem da lista de perguntas abertas; `resposta` é a resposta do usuário " <>
          "(até #{@teto_resposta} caracteres) e, sem ela, vale a sua sugestão. " <>
          "Se a resposta for ambígua, NÃO chame: a pergunta segue aberta.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "questionId" => %{"type" => "string"},
          "resposta" => %{"type" => "string"}
        },
        "required" => ["questionId"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(%{"questionId" => id} = args, ctx) when is_binary(id) and id != "" do
    with {:ok, resposta} <- resposta(Map.get(args, "resposta")) do
      body =
        %{sessionId: ctx.session_id, agentId: ctx.agent}
        |> then(&if(resposta, do: Map.put(&1, :resposta, resposta), else: &1))

      case EngineApiClient.answer_open_question(ctx.project_id, id, body) do
        {:ok, %{"status" => "already_answered"}} ->
          {:ok, "a pergunta #{id} já estava fechada"}

        {:ok, _} ->
          {:ok, "pergunta #{id} fechada com a resposta do usuário"}

        {:error, {404, _}} ->
          {:error, "answer_open_question: a pergunta #{id} não existe neste projeto"}

        {:error, {400, corpo}} ->
          {:error, "answer_open_question: a api recusou o fechamento: #{inspect(corpo)}"}

        {:error, reason} ->
          {:error, "falha ao fechar a pergunta: #{inspect(reason)}"}
      end
    end
  end

  def run(_args, _ctx), do: {:error, "answer_open_question exige `questionId`"}

  defp resposta(nil), do: {:ok, nil}

  defp resposta(r) when is_binary(r) do
    r = String.trim(r)

    cond do
      r == "" ->
        {:ok, nil}

      String.length(r) > @teto_resposta ->
        {:error, "answer_open_question: `resposta` passa de #{@teto_resposta} caracteres"}

      true ->
        {:ok, r}
    end
  end

  defp resposta(_), do: {:error, "answer_open_question: `resposta` precisa ser texto"}
end
