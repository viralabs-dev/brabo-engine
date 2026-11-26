defmodule Engine.Harness.Tools.DeclareOpenQuestion do
  @moduledoc """
  Declara uma PERGUNTA EM ABERTO para o usuário (ADR 0214, RN-862): grava
  `artifact.open_question` no log da sessão, com `questionId` (uuid), a
  pergunta, a sugestão do agente (opcional) e o que ela afeta
  (`afeta: {regras, historias, tarefas}`). É a ÚNICA origem de pergunta em
  aberto — nada é detectado no texto do turno. Quem fecha a pergunta é a api,
  com `open_question.answered`, quando o autor da sessão responde.

  Ferramenta do Criativo, do PO, do Arquiteto e do Dev Lead. A descrição não
  nomeia idioma (RN-667).
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Harness.ArtifactDedupe
  alias Engine.SessionEvents.Event
  alias Engine.Sessions.EngineApiClient

  @teto_pergunta 500
  @teto_sugestao 300
  @chaves_de_afeta ~w(regras historias tarefas)

  @impl true
  def spec do
    %{
      name: "declare_open_question",
      description:
        "Registra uma dúvida que fica para o usuário decidir, com a sua sugestão de " <>
          "resposta e o que ela afeta (ids de regras, histórias e tarefas). A pergunta " <>
          "aparece na fila \"Perguntas em aberto\" e a resposta volta como decisão. " <>
          "`pergunta` até #{@teto_pergunta} caracteres; `sugestao` até #{@teto_sugestao}.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "pergunta" => %{"type" => "string"},
          "sugestao" => %{"type" => "string"},
          "afeta" => %{
            "type" => "object",
            "properties" =>
              Map.new(
                @chaves_de_afeta,
                &{&1, %{"type" => "array", "items" => %{"type" => "string"}}}
              )
          }
        },
        "required" => ["pergunta", "afeta"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(args, ctx) when is_map(args) do
    with {:ok, pergunta} <- pergunta(Map.get(args, "pergunta")),
         {:ok, sugestao} <- sugestao(Map.get(args, "sugestao")),
         {:ok, afeta} <- afeta(Map.get(args, "afeta")),
         :ok <- sem_repeticao(ctx.project_id, pergunta) do
      question_id = Ecto.UUID.generate()

      payload =
        %{
          "questionId" => question_id,
          "pergunta" => pergunta,
          "afeta" => afeta,
          "autor" => ctx.agent,
          "sessionId" => ctx.session_id
        }
        |> then(&if(sugestao, do: Map.put(&1, "sugestao", sugestao), else: &1))

      event = %{
        type: "artifact.open_question",
        actorKind: "agent",
        actorId: ctx.agent,
        payload: payload
      }

      case EngineApiClient.append_event(ctx.project_id, ctx.session_id, event) do
        :ok ->
          {:ok,
           "pergunta em aberto registrada (#{question_id}); o usuário responde pela fila " <>
             "\"Perguntas em aberto\" e a resposta volta como decisão"}

        {:error, reason} ->
          {:error, "falha ao registrar a pergunta: #{inspect(reason)}"}
      end
    end
  end

  def run(_args, _ctx), do: {:error, "declare_open_question exige `pergunta` e `afeta`"}

  # RN-1505: pergunta de texto igual (normalizado) a uma aberta ou já respondida do projeto
  # não é gravada de novo. Paráfrase não é pega (como na ArtifactDedupe). Leitura que falha
  # não barra a pergunta.
  defp sem_repeticao(project_id, pergunta) do
    eventos =
      Event.list_types_for_project(
        project_id,
        ~w(artifact.open_question open_question.answered artifact.decision_record),
        200
      )

    alvo = ArtifactDedupe.normalizar(pergunta)

    respondidas =
      for %{type: "open_question.answered", payload: p} <- eventos,
          into: %{},
          do: {Map.get(p || %{}, "questionId"), p || %{}}

    igual =
      Enum.find(eventos, fn
        %{type: "artifact.open_question", payload: p} ->
          ArtifactDedupe.normalizar(Map.get(p || %{}, "pergunta")) == alvo

        _ ->
          false
      end)

    case igual do
      nil ->
        :ok

      %{payload: %{"questionId" => qid}} ->
        case Map.fetch(respondidas, qid) do
          {:ok, r} ->
            {:error,
             "o usuário já respondeu: #{resposta(r, eventos, qid)}. Siga a decisão; não reabra"}

          :error ->
            {:error, "essa pergunta já está aberta (questionId=#{qid}); espere a resposta"}
        end
    end
  rescue
    _ -> :ok
  end

  defp resposta(r, eventos, qid) do
    decisao =
      Enum.find_value(eventos, fn
        %{type: "artifact.decision_record", payload: %{"context" => c, "choice" => ch}}
        when is_binary(c) ->
          if String.contains?(c, qid), do: ch

        _ ->
          nil
      end)

    to_string(decisao || r["choice"] || r["resposta"] || r["answer"] || "(sem texto)")
  end

  defp pergunta(p) when is_binary(p) do
    p = String.trim(p)

    cond do
      p == "" ->
        {:error, "declare_open_question: `pergunta` vazia"}

      String.length(p) > @teto_pergunta ->
        {:error, "declare_open_question: `pergunta` passa de #{@teto_pergunta} caracteres"}

      true ->
        {:ok, p}
    end
  end

  defp pergunta(_), do: {:error, "declare_open_question exige `pergunta` (texto)"}

  defp sugestao(nil), do: {:ok, nil}

  defp sugestao(s) when is_binary(s) do
    s = String.trim(s)

    cond do
      s == "" ->
        {:ok, nil}

      String.length(s) > @teto_sugestao ->
        {:error, "declare_open_question: `sugestao` passa de #{@teto_sugestao} caracteres"}

      true ->
        {:ok, s}
    end
  end

  defp sugestao(_), do: {:error, "declare_open_question: `sugestao` precisa ser texto"}

  defp afeta(a) when is_map(a) do
    desconhecidas = Map.keys(a) -- @chaves_de_afeta

    cond do
      desconhecidas != [] ->
        {:error,
         "declare_open_question: `afeta` aceita só regras, historias e tarefas — recebeu " <>
           Enum.join(desconhecidas, ", ")}

      true ->
        Enum.reduce_while(@chaves_de_afeta, {:ok, %{}}, fn chave, {:ok, acc} ->
          case Map.get(a, chave, []) do
            ids when is_list(ids) ->
              if Enum.all?(ids, &(is_binary(&1) and &1 != "")),
                do: {:cont, {:ok, Map.put(acc, chave, ids)}},
                else:
                  {:halt, {:error, "declare_open_question: `afeta.#{chave}` exige ids (texto)"}}

            _ ->
              {:halt, {:error, "declare_open_question: `afeta.#{chave}` precisa ser lista"}}
          end
        end)
    end
  end

  defp afeta(_),
    do: {:error, "declare_open_question exige `afeta` (objeto com regras, historias, tarefas)"}
end
