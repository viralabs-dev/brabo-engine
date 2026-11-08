defmodule Engine.Harness.DecisoesDoProjeto do
  @moduledoc """
  As DECISÕES do usuário e as perguntas ABERTAS do projeto, no turno do PO
  (RN-874, AT-526). Sem isto o PO escrevia "pergunta em aberto 1" numa
  história criada depois de o usuário já ter respondido a pergunta: ele não
  lia `decision_record` nem `open_question.answered`.

  Segue o caminho efêmero do fluxo do time (RN-711): a fachada
  `Engine.Sessions.EngineApiClient` acrescenta o texto como mensagem `system`
  no fim da lista, depois do fluxo — nunca em `state.messages` nem no prompt
  do servidor. Para os quatro perguntadores (RN-1003: precisam do `questionId` para `answer_open_question`).

  Leitura LOCAL do event log (`Event.list_types_for_project/3`, Postgres
  direto, sem HTTP no laço — a régua da RN-566), do projeto inteiro: aberta é
  `artifact.open_question` sem `open_question.answered` com o mesmo
  `questionId`. Teto: 10 decisões, 10 perguntas, 240 caracteres por item,
  3 000 no texto. Leitura que falha ou nada a dizer = lista intacta, nunca
  queda do turno.
  """

  alias Engine.SessionEvents.Event

  @agentes ~w(criativo po arquiteto dev-lead)
  @teto_itens 10
  @teto_item 240
  @teto 3000
  @leitura 200

  @doc "O teto em caracteres do texto acrescentado."
  def teto_de_caracteres, do: @teto

  @doc "A lista com as decisões/perguntas no FIM, ou intacta (outro agente, nada a dizer, falha)."
  @spec anexar([map()], term(), String.t()) :: [map()]
  def anexar(messages, project_id, agent)
      when is_list(messages) and agent in @agentes and is_binary(project_id) do
    case texto(project_id) do
      nil -> messages
      t -> messages ++ [%{"role" => "system", "content" => t}]
    end
  rescue
    _ -> messages
  catch
    :exit, _ -> messages
  end

  def anexar(messages, _project_id, _agent), do: messages

  @doc "O texto para o projeto, ou `nil` sem decisão nem pergunta aberta. Público para teste."
  def texto(project_id) do
    eventos =
      Event.list_types_for_project(
        project_id,
        ["artifact.decision_record", "artifact.open_question", "open_question.answered"],
        @leitura
      )

    todas = abertas(eventos)

    decisoes =
      for(%{type: "artifact.decision_record", payload: p} <- eventos, do: p || %{})
      |> Enum.take(-@teto_itens)
      |> Enum.map(fn p ->
        "- " <>
          curto("#{Map.get(p, "choice", "")} (contexto: #{Map.get(p, "context", "")})") <>
          origem(p)
      end)

    montar(decisoes, Enum.map(Enum.take(todas, -@teto_itens), &linha_aberta/1), length(todas))
  end

  @doc """
  As perguntas ABERTAS (AT-804): `artifact.open_question` sem `open_question.answered`
  com o mesmo `questionId`, de qualquer autor, mais antigas primeiro. Cada item é
  `%{payload: map, autor: String.t() | nil}`. Compartilhada com `list_open_questions`.
  """
  def abertas(eventos) do
    respondidas =
      for %{type: "open_question.answered", payload: p} <- eventos,
          into: MapSet.new(),
          do: Map.get(p || %{}, "questionId")

    for %{type: "artifact.open_question", payload: p} = e <- eventos,
        not MapSet.member?(respondidas, Map.get(p || %{}, "questionId")),
        do: %{payload: p || %{}, autor: Map.get(e, :actor_id)}
  end

  @doc "A linha de uma pergunta aberta (questionId inteiro, pergunta e sugestão curtas)."
  def linha_aberta(%{payload: p}) do
    "- questionId=#{Map.get(p, "questionId")}: " <>
      curto(to_string(Map.get(p, "pergunta", ""))) <>
      case Map.get(p, "sugestao") do
        s when is_binary(s) and s != "" -> " (sugestão: #{curto(s)})"
        _ -> ""
      end
  end

  # `questionId` e histórias afetadas: é o que o PO cita em `complete_story`/`update_story`
  # para corrigir história `ready` (RN-859, AT-752). Fora do teto do item, para não ser cortado.
  defp origem(p) do
    historias =
      case get_in(p, ["afeta", "historias"]) do
        l when is_list(l) and l != [] -> "; histórias: " <> Enum.join(l, ", ")
        _ -> ""
      end

    case Map.get(p, "questionId") do
      q when is_binary(q) and q != "" -> " [questionId=#{q}#{historias}]"
      _ -> ""
    end
  end

  defp montar([], [], _total), do: nil

  # AT-804 (RN-874): as ABERTAS vêm antes das decisões e o corte é por LINHA
  # inteira — nunca no meio de um `questionId`. Pergunta que não coube é dita.
  defp montar(decisoes, abertas, total) do
    intro =
      "DECISÕES E PERGUNTAS DO PROJETO. Ao escrever história, regra, DoR, DoD ou " <>
        "tarefa, use a RESPOSTA decidida — nunca escreva \"pergunta em aberto N\"."

    cab_abertas =
      "Perguntas AINDA abertas (#{total} no total; não invente a resposta; cite o " <>
        "questionId no que depende dela):"

    cab_decisoes = "Decisões do usuário:"
    reserva = 200
    livre = @teto - String.length(intro) - String.length(cab_abertas) - reserva
    {abertas_ok, livre} = caber(abertas, livre)
    {decisoes_ok, _} = caber(Enum.reverse(decisoes), livre - String.length(cab_decisoes) - 4)

    aviso =
      if length(abertas_ok) < total,
        do:
          "Há #{total} perguntas abertas no total; #{length(abertas_ok)} listadas acima; " <>
            "use `list_open_questions` para ver todas."

    [
      intro,
      if(abertas_ok != [], do: cab_abertas <> "\n" <> Enum.join(abertas_ok, "\n")),
      aviso,
      if(decisoes_ok != [],
        do: cab_decisoes <> "\n" <> Enum.join(Enum.reverse(decisoes_ok), "\n")
      )
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  # Linhas na ordem dada enquanto couberem no orçamento; a primeira que estoura encerra.
  defp caber(linhas, orcamento) do
    Enum.reduce_while(linhas, {[], orcamento}, fn l, {acc, o} ->
      custo = String.length(l) + 1
      if custo <= o, do: {:cont, {acc ++ [l], o - custo}}, else: {:halt, {acc, o}}
    end)
  end

  defp curto(s) do
    s = String.trim(s)
    if String.length(s) > @teto_item, do: String.slice(s, 0, @teto_item - 1) <> "…", else: s
  end
end
