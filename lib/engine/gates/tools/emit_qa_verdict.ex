defmodule Engine.Gates.Tools.EmitQaVerdict do
  @moduledoc """
  Registra o parecer do QAAgent (Fase 4a): `veredito` (`approved`/
  `changes_requested`), `resumo`, `itens` (só o que bloqueia), `melhorias` (o que não bloqueia) e a
  `coverageMatrix` (regra → testes que a cobrem). ENFORÇADO como
  `Engine.Dev.Tools.ReportDone`: só aceita `approved` se a ÚLTIMA mensagem
  `tool` "terminal" no histórico começar com "exit 0" — `changes_requested`
  é sempre aceito (reprovar nunca precisa de prova).
  """

  @behaviour Engine.Harness.Tool

  @impl true
  def spec do
    %{
      name: "emit_qa_verdict",
      description:
        "Registra o parecer de QA (aprovado ou mudanças solicitadas) com a matriz " <>
          "de cobertura regra→testes. Só aceito aprovar com a suite verde (exit 0). " <>
          "`needs_user_decision` quando o requisito depende de decisão do usuário: " <>
          "exige `pergunta` (e a sua `sugestao`) ou `openQuestionId` de uma pergunta existente.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "veredito" => %{
            "type" => "string",
            "enum" => ["approved", "changes_requested", "needs_user_decision"]
          },
          "pergunta" => %{"type" => "string"},
          "sugestao" => %{"type" => "string"},
          "openQuestionId" => %{"type" => "string"},
          "opcoes" => %{
            "type" => "array",
            "description" =>
              "só em `needs_user_decision`: até 2 opções prontas, cada uma `{rotulo, resposta}` " <>
                "(rótulo de 2 a 6 palavras do dia a dia, até 40 caracteres, que resume a RESPOSTA, " <>
                "como \"Não deixar cancelar\", nunca \"Recusar\"); viram botões de resposta em um clique",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "rotulo" => %{"type" => "string"},
                "resposta" => %{"type" => "string"}
              },
              "required" => ["rotulo", "resposta"]
            }
          },
          "detalhe" => %{
            "type" => "string",
            "description" => "só em `needs_user_decision`: relato técnico, que fica recolhido"
          },
          "resumo" => %{"type" => "string"},
          "itens" => %{
            "type" => "array",
            "description" =>
              "SÓ o que BLOQUEIA (viola regra da história, critério da tarefa ou RN do recorte). " <>
                "Cada item é texto, ou {texto, origem} com origem `anterior` ou `regressao_no_diff`; " <>
                "em volta nova, item novo é `regressao_no_diff` e cita um arquivo do diff da volta.",
            "items" => %{
              "anyOf" => [
                %{"type" => "string"},
                %{
                  "type" => "object",
                  "properties" => %{
                    "texto" => %{"type" => "string"},
                    "origem" => %{"type" => "string", "enum" => ["anterior", "regressao_no_diff"]}
                  },
                  "required" => ["texto"]
                }
              ]
            }
          },
          "melhorias" => %{
            "type" => "array",
            "description" => "sugestões que NÃO bloqueiam e não contam correção",
            "items" => %{"type" => "string"}
          },
          "relatorioDeTestes" => %{
            "type" => "string",
            "description" => "caminho relativo do relatório JUnit gerado (opcional)"
          },
          "coverageMatrix" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "rule" => %{"type" => "string"},
                "tests" => %{"type" => "array", "items" => %{"type" => "string"}},
                "covered" => %{"type" => "boolean"},
                "motivo" => %{
                  "type" => "string",
                  "enum" => ["outra_tarefa", "aceito_pelo_dono"],
                  "description" =>
                    "só para `covered: false`: regra de OUTRA tarefa, ou teste pulado que o dono aceitou"
                },
                "justificativa" => %{"type" => "string"}
              },
              "required" => ["rule", "tests", "covered"]
            }
          }
        },
        "required" => ["veredito", "resumo", "itens", "coverageMatrix"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(%{"veredito" => "approved"} = args, ctx) do
    case last_terminal_content(Map.get(ctx, :messages, [])) do
      "exit 0" <> _ ->
        case recusa_da_matriz(Map.get(args, "coverageMatrix"), ctx) do
          nil -> {:ok, "parecer registrado: aprovado"}
          msg -> {:error, msg}
        end

      _ ->
        {:error,
         "não é possível aprovar: nenhum `terminal` com exit 0 (suite verde) encontrado no histórico"}
    end
  end

  # AT-905 (RN-1117): reprovar exige ao menos um item BLOQUEANTE.
  def run(%{"veredito" => "changes_requested"} = args, _ctx) do
    if Engine.Gates.Hooks.Termination.lista(Map.get(args, "itens")) == [],
      do:
        {:error,
         "`changes_requested` sem item bloqueante em `itens`: aprove (`approved`) e " <>
           "liste o que sobrou em `melhorias`"},
      else: {:ok, "parecer registrado: mudanças solicitadas"}
  end

  # ADR 0214 (RN-862): requisito não confirmado pelo usuário não é defeito do
  # dev — é pergunta. Sem pergunta nem pergunta existente, é recusa nomeada.
  # AT-526 (RN-876): `openQuestionId` que não é uuid ("1") a api recusa com
  # 400 — a recusa vem aqui, dentro do laço, antes de chamar a api.
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def run(%{"veredito" => "needs_user_decision", "openQuestionId" => id}, _ctx)
      when is_binary(id) and id != "" do
    if Regex.match?(@uuid, id),
      do: {:ok, "parecer registrado: decisão do usuário pedida"},
      else:
        {:error,
         "`openQuestionId` \"#{id}\" não é o uuid de uma pergunta aberta: " <>
           "use o uuid exato de uma pergunta ABERTA, ou mande a pergunta nova em " <>
           "`pergunta`/`sugestao` sem `openQuestionId`"}
  end

  def run(%{"veredito" => "needs_user_decision"} = args, _ctx) do
    pergunta = Map.get(args, "pergunta")
    existente = Map.get(args, "openQuestionId")

    if (is_binary(pergunta) and String.trim(pergunta) != "") or
         (is_binary(existente) and existente != ""),
       do: opcoes_e_detalhe(args),
       else:
         {:error,
          "needs_user_decision exige `pergunta` (com a sua `sugestao`) ou `openQuestionId`"}
  end

  def run(_args, _ctx),
    do: {:error, "emit_qa_verdict exige veredito, resumo, itens e coverageMatrix"}

  # AT-1021 (RN-1530): `opcoes` e `detalhe` da pergunta nova; com `opcoes`, a pergunta é
  # para leigo. Recusa volta ao modelo, que reescreve.
  defp opcoes_e_detalhe(args) do
    pergunta = Map.get(args, "pergunta")

    with {:ok, opcoes} <- Engine.Dev.ExplicacaoDoBloqueio.opcoes(Map.get(args, "opcoes")),
         {:ok, _} <- Engine.Dev.ExplicacaoDoBloqueio.detalhe(Map.get(args, "detalhe")),
         :ok <- pergunta_para_leigo(pergunta, opcoes) do
      {:ok, "parecer registrado: decisão do usuário pedida"}
    end
  end

  defp pergunta_para_leigo(pergunta, [_ | _]) when is_binary(pergunta) do
    case Engine.Dev.ExplicacaoDoBloqueio.sem_jargao(pergunta) do
      :ok ->
        :ok

      {:error, motivo} ->
        {:error,
         "com `opcoes`, a `pergunta` é para quem não programa (#{motivo}); mova o técnico para `detalhe`"}
    end
  end

  defp pergunta_para_leigo(_pergunta, _opcoes), do: :ok

  # AT-1023 (RN-1513): a matriz é régua de `approved`. Linha sem prova só passa
  # com `motivo` (`outra_tarefa`, ou `aceito_pelo_dono` com decisão da tarefa).
  defp recusa_da_matriz(matriz, ctx) do
    linhas = Enum.filter(Engine.Gates.Hooks.Termination.lista(matriz), &is_map/1)
    decisoes = Map.get(ctx, :decisoes) || []
    esperadas = length(Map.get(ctx, :regras) || []) + length(decisoes)
    sem_prova = Map.get(ctx, :testes_sem_prova) || []

    cond do
      linha = Enum.find(linhas, &(&1["covered"] != true and is_nil(&1["motivo"]))) ->
        "não é possível aprovar: a regra «#{linha["rule"]}» não tem teste que a prove. " <>
          "Reprove (`changes_requested`, com a regra em `itens`) ou, se ela é de outra " <>
          "tarefa, marque `motivo: outra_tarefa`."

      linha = Enum.find(linhas, &(&1["motivo"] == "aceito_pelo_dono" and decisoes == [])) ->
        "não é possível aprovar: a regra «#{linha["rule"]}» diz `aceito_pelo_dono`, mas " <>
          "não há decisão do dono registrada nesta tarefa. Reprove (`changes_requested`)."

      linha = Enum.find(linhas, &(&1["covered"] == true and so_sem_prova?(&1, sem_prova))) ->
        "não é possível aprovar: os testes da regra «#{linha["rule"]}» terminam antes de " <>
          "conferir qualquer coisa (retorno antecipado). Reprove (`changes_requested`, " <>
          "com a regra em `itens`) ou use `covered: false` e o `motivo` cabível."

      length(linhas) < esperadas ->
        "não é possível aprovar: faltam #{esperadas - length(linhas)} regras na matriz. " <>
          "Cada regra da história e cada decisão do dono desta tarefa é uma linha da " <>
          "`coverageMatrix`."

      true ->
        nil
    end
  end

  defp so_sem_prova?(%{"tests" => [_ | _] = tests} = linha, sem_prova),
    do:
      is_nil(linha["motivo"]) and
        Enum.all?(tests, fn t -> Enum.any?(sem_prova, &(t == &1 or String.ends_with?(t, &1))) end)

  defp so_sem_prova?(_, _), do: false

  defp last_terminal_content(messages) do
    messages
    |> Enum.filter(&(Map.get(&1, "role") == "tool" and Map.get(&1, "name") == "terminal"))
    |> List.last()
    |> case do
      nil -> nil
      msg -> Map.get(msg, "content")
    end
  end
end
