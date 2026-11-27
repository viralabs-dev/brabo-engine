defmodule Engine.Agents.DevLeadTools do
  @moduledoc """
  As ferramentas do Dev Lead: propor o PLANO de execução (FASE 14d item 5,
  ADR 0053) e avaliar a IMPLEMENTABILIDADE de uma story (ADR 0090).

  Ele não escreve código — distribui trabalho e responde por ele. O plano diz
  quantos agentes por módulo e **por quê**, e — desde a RN-678 (AT-274) — de
  QUAL módulo é cada tarefa (`tarefas`, `[{taskId, modulo}]`): é por essa
  atribuição que só o `dev-<modulo>` certo pega a tarefa.

  ## Aprovar o plano ATIVA a execução (AT-263, RN-677, ADR 0194)

  Revisão da RN-161: o aceite do handoff ao Dev Lead só o traz para PLANEJAR.
  A ativação da execução (dev agents, worktrees, gasto) acontece quando o
  humano APROVA este `propose_execution_plan` — a api ganhou o executor
  (`ExecuteExecutionPlanUseCase`), que grava o módulo das tarefas e chama o
  MESMO `ActivateExecutionUseCase` do botão. A api valida o plano contra o
  `module_map` vigente já na PROPOSTA (400 `plano_de_execucao_invalido`), e a
  frase dela volta ao modelo como erro da ferramenta, para ele corrigir.

  ## O plano é `proposed_action` (ADR 0086, RN-284) — revisão da decisão original

  Até aqui o plano virava EVENTO simples no log
  (`execution.plan_proposed`), sem pipeline de aprovação: o argumento era que
  propor um plano não tem efeito externo nenhum — o gasto acontece quando os
  agentes sobem, e era lá que o teto da RN-083 cobrava autorização.
  Transformar a proposta em ação a decidir faria o usuário decidir duas vezes
  a mesma coisa.

  A auditoria de `docs/fluxo.yml` × código (achado A2) encontrou que
  `fluxo.yml` já declarava esta saída como `via: proposed_action` desde a
  ADR 0085, e o código nunca foi ajustado para bater. O dono do produto
  decidiu que o código erra: o plano é a PRIMEIRA decisão real de quanto a
  sessão vai gastar com paralelismo (RN-083 nasce aqui, não só na
  ultrapassagem de teto) — o usuário decide ativar a execução tendo VISTO o
  plano numa aprovação de verdade, não só lido uma linha no fio. A lição
  antiga ("decidir duas vezes") não desapareceu: ela é o motivo pelo qual
  `propose_execution_plan` NÃO entrou no bloco de tetos absolutos de
  `decide.ts` — pode ser configurado para auto-aprovar, ao contrário de
  `parallelize`/`raise_max_parallel`, que nunca podem.

  `run/2` agora chama `EngineApiClient.propose_action/5` em vez de
  `append_event/3`, e o chamador (`Engine.Agents.DevLeadServer`) SUSPENDE o
  turno até a decisão — ver o moduledoc de lá para o mecanismo.

  ## `assess_implementability` (ADR 0090) — o gate `implementavel` ativo

  `docs/gates.yml` declarava o gate `implementavel` como `status: planned`
  desde a FASE 14d (dono `dev-lead`, entregável `parecer-implementabilidade`)
  — nunca ativado. Esta ferramenta ativa: `run_assessment/2` monta o parecer
  e chama `EngineApiClient.propose_action/5` com `"assess_implementability"`,
  MESMO padrão de `run/2`/`propose_execution_plan` acima (contrato de três
  desfechos, `{:ok, texto} | {:pending, action_id} | {:error, texto}`).

  ### O insumo é a story e o `module_map`, não o plano de teste (ADR 0192)

  O ADR 0090 fazia o parecer depender do `artifact.plano_de_teste` da story:
  sem plano, esta ferramenta disparava a QA-estratégia e devolvia erro
  pedindo para chamar de novo. No uso real de 29/09 o plano NUNCA chegou —
  a QA-estratégia esgotou o teto de 8 iterações procurando um código que
  ainda não existia — e o Dev Lead ficou sem parecer. O dono decidiu (01/10)
  que o plano de teste nasce DEPOIS da entrega do dev (RN-674), e o gate
  perdeu aquele insumo. O que o substitui é o que o Dev Lead JÁ tem no
  contexto do próprio turno: a história (RF, RNF, DoD) e o `module_map`
  vigente, que o kickoff dele lista. O julgamento é dele, na `justificativa`
  — a ferramenta não busca nada para isso, e o parecer sai na PRIMEIRA
  chamada. O payload perdeu `planoDeTeste`/`criteriosExecutaveis`: não há
  plano para embutir antes do código.

  ### O appsec dispara junto, e NÃO é pré-requisito (RN-539)

  `Engine.Gates.SecOpsAgentServer.run_design/2` — o threat model STRIDE-lite
  de DESIGN (appsec, RN-360, mesmo ADR 0090) — nasceu ACIONÁVEL e sem
  chamador de produção nenhum: `docs/fluxo.yml` declarava a lacuna e já
  nomeava ESTE ponto como o gatilho natural. É ele agora, por
  `Engine.Gates.Dispatcher.run_appsec_design/2`.

  Ele dispara em PARALELO à proposta do parecer, e o parecer NÃO espera por
  ele. Fazer o parecer depender do threat model faria o gate `implementavel`
  depender de uma produção assíncrona — exatamente a espera que o ADR 0192
  tirou do plano de teste. O threat model chega a quem
  precisa pelo caminho que a RN-361 já definiu — handoff para `arquiteto`,
  `dev-lead` e `infra` —, não por este retorno.

  A idempotência é obrigatória, e é o que `disparar_appsec_se_preciso/3`
  guarda: o modelo pode reavaliar a mesma story (ou repetir a chamada depois
  de um erro), e sem a guarda cada rechamada custaria mais uma rodada de LLM
  e mais três handoffs sobre a mesma story.
  """

  alias Engine.Agents.Reidratacao
  alias Engine.Gates.Dispatcher
  alias Engine.Harness.IdDoBacklog
  alias Engine.Harness.RotasDoContrato
  alias Engine.Sessions.EngineApiClient

  @spec spec() :: map()
  def spec do
    %{
      name: "propose_execution_plan",
      description:
        "Propõe o plano de execução: quantos agentes por módulo e por quê. " <>
          "Use UMA vez, depois de avaliar o module_map e o backlog pegável, e " <>
          "atribua cada tarefa a um módulo em `tarefas`. É uma decisão real, que " <>
          "o usuário aprova ou recusa em Aprovações — APROVAR é o que ativa a " <>
          "execução (sobe os dev agents), e a conversa espera a decisão antes " <>
          "de continuar.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "modulos" => %{
            "type" => "array",
            "description" => "um item por módulo que você quer trabalhar agora",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "modulo" => %{"type" => "string"},
                "agentes" => %{
                  "type" => "integer",
                  "minimum" => 1,
                  "description" =>
                    "quantos agentes você recomenda neste módulo. Mais de 1 só passa com " <>
                      "tarefas levantadas (`levantar_tarefa`) que não dependem entre si e " <>
                      "têm `arquivos` disjuntos: no mínimo `agentes` delas (RN-1380). " <>
                      "Fora disso, UM dev agent por módulo"
                },
                "porque" => %{
                  "type" => "string",
                  "description" =>
                    "o que no backlog justifica esse número. Cite tarefas pelo TÍTULO, " <>
                      "não pelo id: os ids vão só em `tarefas[].taskId`, que o sistema confere"
                }
              },
              "required" => ["modulo", "agentes", "porque"]
            }
          },
          "resumo" => %{
            "type" => "string",
            "description" => "o plano em uma frase, para o usuário decidir sem ler a lista"
          },
          "tarefas" => %{
            "type" => "array",
            "description" =>
              "TODA tarefa pendente do backlog, cada uma com o módulo (do module_map) " <>
                "cujo dev agent vai pegá-la — só o dev daquele módulo pega a tarefa",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "taskId" => %{
                  "type" => "string",
                  "description" => "o task_id da lista de tarefas"
                },
                "modulo" => %{"type" => "string", "description" => "um módulo do module_map"},
                "depende_de" => %{
                  "type" => "array",
                  "items" => %{"type" => "string"},
                  "description" =>
                    "task_id das tarefas que expõem o que esta consome (RN-1379); " <>
                      "vazio = vale a ordem do módulo. Exige `levantar_tarefa` em TODAS as tarefas do plano"
                }
              },
              "required" => ["taskId", "modulo"]
            }
          }
        },
        "required" => ["modulos", "resumo", "tarefas"]
      }
    }
  end

  @spec run(map(), map()) :: {:ok, String.t()} | {:pending, String.t()} | {:error, String.t()}
  def run(%{"modulos" => modulos, "resumo" => resumo} = args, state) when is_list(modulos) do
    case validar(modulos) do
      {:error, motivo} ->
        {:error, motivo}

      {:ok, normalizados} ->
        # RN-721: o `taskId` encurtado (prefixo >= 8 hex) vira o UUID antes
        # de ir à api; o resto de `tarefas` vai como veio.
        case resolver_tarefas(state.project_id, Map.get(args, "tarefas", [])) do
          {:error, motivo} ->
            {:error, motivo}

          {:ok, tarefas} ->
            with :ok <- conferir_levantamento(state.project_id, normalizados, tarefas),
                 do: restantes_e_conferir(state, normalizados, resumo, tarefas)
        end
    end
  end

  def run(_args, _state),
    do: {:error, "propose_execution_plan exige `modulos` (lista) e `resumo`"}

  # RN-1130 (AT-910): com a execução ativa, o plano vira "plano das tarefas
  # restantes" — sai o que já está feito/em curso ou já tem o mesmo módulo; sem
  # sobra, recusa. Falha de leitura (banco ou backlog) não recusa, como a RN-792.
  defp restantes_e_conferir(state, normalizados, resumo, tarefas) do
    with [_ | _] <- tarefas,
         true <- execucao_ativa?(state.project_id),
         {:ok, epicos} when is_list(epicos) <- EngineApiClient.list_backlog(state.project_id) do
      atuais =
        Map.new(
          for e <- epicos, h <- Map.get(e, "stories") || [], t <- Map.get(h, "tasks") || [] do
            {Map.get(t, "id"), t}
          end
        )

      case Enum.reject(tarefas, &ja_resolvida?(Map.get(atuais, &1["taskId"]), &1)) do
        [] ->
          {:error,
           "plano recusado: a execução já está ativa e todas as tarefas têm dono ou já andam. " <>
             "NÃO reproponha: diga ao usuário o que destrava (Rearmar, \"Tentar de novo\", responder)."}

        sobra ->
          resumo = "plano das tarefas restantes (#{length(sobra)}): #{resumo}"
          conferir_donos(state, normalizados, resumo, sobra)
      end
    else
      _ -> conferir_donos(state, normalizados, resumo, tarefas)
    end
  end

  defp execucao_ativa?(project_id) do
    Engine.Dev.DevAgentState.list_by_project(project_id) != []
  rescue
    _ -> false
  end

  defp ja_resolvida?(%{"status" => status} = t, %{"modulo" => modulo}),
    do: status in ~w(done in_progress in_review) or Map.get(t, "module") == modulo

  defp ja_resolvida?(_t, _tarefa), do: false

  defp resolver_tarefas(project_id, tarefas) when is_list(tarefas) do
    Enum.reduce_while(tarefas, {:ok, []}, fn
      %{"taskId" => id} = t, {:ok, acc} ->
        with {:ok, uuid} <- IdDoBacklog.resolver(project_id, :tarefa, id),
             {:ok, deps} <- resolver_deps(project_id, t) do
          {:cont, {:ok, [t |> Map.put("taskId", uuid) |> Map.merge(deps) | acc]}}
        else
          {:error, motivo} -> {:halt, {:error, motivo}}
        end

      t, {:ok, acc} ->
        {:cont, {:ok, [t | acc]}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      erro -> erro
    end
  end

  defp resolver_tarefas(_project_id, tarefas), do: {:ok, tarefas}

  # RN-1379: `depende_de` também vem encurtado; sai como `dependeDe` (o que a api lê).
  defp resolver_deps(project_id, t) do
    case t |> Map.take(["depende_de", "dependeDe"]) |> Map.values() do
      [] ->
        {:ok, %{}}

      [deps | _] ->
        Enum.reduce_while(List.wrap(deps), {:ok, []}, fn id, {:ok, acc} ->
          case IdDoBacklog.resolver(project_id, :tarefa, id) do
            {:ok, uuid} -> {:cont, {:ok, acc ++ [uuid]}}
            erro -> {:halt, erro}
          end
        end)
        |> case do
          {:ok, uuids} -> {:ok, %{"dependeDe" => uuids}}
          erro -> erro
        end
    end
  end

  # RN-1379/RN-1380: antes de propor, toda tarefa `todo` do plano precisa de
  # levantamento, e módulo com `agentes` > 1 precisa de lote disjunto. Falha de
  # leitura não recusa (a api reconfere), como a RN-792.
  defp conferir_levantamento(_project_id, _normalizados, []), do: :ok

  defp conferir_levantamento(project_id, normalizados, tarefas) do
    case EngineApiClient.list_backlog(project_id) do
      {:ok, epicos} when is_list(epicos) ->
        atuais =
          Map.new(
            for e <- epicos, h <- Map.get(e, "stories") || [], t <- Map.get(h, "tasks") || [] do
              {Map.get(t, "id"), t}
            end
          )

        sem =
          for p <- tarefas,
              %{"status" => "todo", "levantamento" => nil} = t <- [Map.get(atuais, p["taskId"])],
              do: "#{Map.get(t, "title")} (#{p["taskId"]})"

        if sem == [],
          do: conferir_lotes(normalizados, tarefas, atuais),
          else:
            {:error,
             "plano recusado: tarefa sem levantamento (RN-1379): #{Enum.join(sem, "; ")}. " <>
               "Chame `levantar_tarefa` em cada uma (arquivos, expoe, consome, dependencias_npm, " <>
               "aceite) e proponha o plano de novo."}

      _ ->
        :ok
    end
  end

  defp conferir_lotes(normalizados, tarefas, atuais) do
    Enum.find_value(normalizados, :ok, fn %{modulo: modulo, agentes: agentes} ->
      do_modulo = Enum.filter(tarefas, &(&1["modulo"] == modulo))

      lote =
        for p <- do_modulo,
            %{"levantamento" => %{"arquivos" => arquivos}} = t <- [Map.get(atuais, p["taskId"])] do
          %{
            id: p["taskId"],
            titulo: Map.get(t, "title"),
            arquivos: arquivos,
            deps: Map.get(p, "dependeDe") || Map.get(t, "dependeDe") || []
          }
        end

      with true <- agentes > 1 and length(lote) == length(do_modulo),
           {:error, motivo} <- Engine.Agents.LoteDisjunto.conferir(lote, agentes) do
        {:error,
         "plano recusado: módulo #{modulo} pede #{agentes} agentes (RN-1380): #{motivo} " <>
           "Reduza `agentes` ou separe os arquivos das tarefas."}
      else
        _ -> nil
      end
    end)
  end

  # RN-1011: ANTES de propor (no modo automático a proposta já executa), recusa
  # a tarefa que cita rota que o contrato vigente declara em OUTRO módulo.
  # Falha de leitura não recusa: o plano segue com aviso, como na RN-792.
  defp conferir_donos(state, normalizados, resumo, tarefas) do
    with {:ok, %{"modulos" => contratos}} <-
           EngineApiClient.list_module_contracts(state.project_id),
         {:ok, epicos} <- EngineApiClient.list_backlog(state.project_id) do
      backlog =
        for e <- epicos, h <- Map.get(e, "stories") || [], t <- Map.get(h, "tasks") || [], do: t

      case RotasDoContrato.donos_divergentes(contratos, backlog, tarefas) do
        [] ->
          propor_plano(state, normalizados, resumo, tarefas)

        linhas ->
          {:error,
           "plano recusado: tarefa de rota fora do módulo dono (RN-1011):\n" <>
             Enum.join(linhas, "\n") <>
             "\nMova a tarefa para o módulo dono da rota ou separe a parte de domínio " <>
             "numa tarefa do módulo de domínio com `create_task`, e proponha o plano de novo."}
      end
    else
      _ ->
        with {:ok, msg} <- propor_plano(state, normalizados, resumo, tarefas),
             do: {:ok, msg <> "\n(aviso: não consegui conferir o dono das rotas no contrato)"}
    end
  end

  defp propor_plano(state, normalizados, resumo, tarefas) do
    total = Enum.reduce(normalizados, 0, &(&1.agentes + &2))
    actor = %{kind: "agent", id: "dev-lead"}

    # `tarefas` é conferida pela API, contra o `module_map` vigente
    # (RN-678) — uma régua só, e a frase da recusa dela volta ao modelo
    # (`erro_da_proposta/1`).
    payload = %{
      modulos: normalizados,
      resumo: resumo,
      totalAgentes: total,
      tarefas: tarefas
    }

    case EngineApiClient.propose_action(
           state.project_id,
           state.session_id,
           "propose_execution_plan",
           actor,
           payload
         ) do
      {:ok, action} ->
        classificar(Map.get(action, "status"), action, total, normalizados)

      {:error, reason} ->
        {:error, erro_da_proposta(reason)}
    end
  end

  # A recusa NOMEADA da api (RN-678): tarefa sem módulo, módulo fora do
  # `module_map`, tarefa que não é do projeto. A frase vai ao modelo como está,
  # com o que fazer — é entrada do laço (RN-163), e ele corrige o plano.
  defp erro_da_proposta({400, %{"code" => "plano_de_execucao_invalido", "message" => motivo}}),
    do:
      "plano recusado: #{motivo} Chame `read_backlog` para reler as tarefas e o " <>
        "module_map, corrija `tarefas` e proponha o plano de novo."

  defp erro_da_proposta(reason),
    do: "não consegui propor o plano de execução: #{inspect(reason)}"

  # Desde a RN-677 (AT-263, ADR 0194) `propose_execution_plan` TEM pipeline
  # na api: aprovar (ou auto-aprovar) grava o módulo das tarefas e ATIVA a
  # execução, e a ação termina `executed` (com a sessão de execução no
  # `executionResult`) ou `failed` (com o motivo). Auto-aprovado, a api já
  # executa na proposta e devolve o desfecho aqui; `"auto_approved"`/
  # `"approved"` seguem contando como sucesso para não chamar de erro uma ação
  # cujo desfecho ainda não chegou.
  defp classificar("executed", action, total, normalizados) do
    {:ok,
     "plano aprovado e execução ATIVADA: #{sobem(total, normalizados)}; cada tarefa " <>
       "vai para o dev do módulo atribuído." <>
       resumo_do_plano(Map.get(action, "executionResult") || %{})}
  end

  defp classificar(status, _action, total, normalizados)
       when status in ["auto_approved", "approved"] do
    {:ok, "plano aprovado: #{sobem(total, normalizados)}. A aprovação ativa a execução."}
  end

  defp classificar("failed", action, _total, _normalizados) do
    motivo = get_in(action, ["executionResult", "motivo"]) || "sem motivo registrado"

    {:error,
     "o plano foi aprovado, mas a ativação da execução falhou: #{motivo}. " <>
       "Diga ao usuário o que falta."}
  end

  defp classificar("pending", %{"id" => action_id}, _total, _normalizados)
       when is_binary(action_id) do
    {:pending, action_id}
  end

  defp classificar(status, _action, _total, _normalizados) do
    {:error, "o plano não foi registrado (status inesperado: #{inspect(status)})"}
  end

  # RN-747 (AT-437): a ativação sobe UM dev agent por módulo; o número que o
  # plano pede além disso é paralelização (teto RN-154), decisão do usuário.
  defp sobem(total, normalizados) do
    n = length(normalizados)
    base = "#{n} dev agent(s) sobem, um por módulo"

    if total > n,
      do:
        base <>
          " (o plano pedia #{total}; os #{total - n} a mais NÃO sobem com a aprovação — " <>
          "paralelizar é decisão do usuário, não diga que há paralelismo)",
      else: base
  end

  # Plano vazio, ou com zero agente num módulo, não é plano — e chegaria ao
  # usuário como uma decisão sem conteúdo.
  defp validar([]), do: {:error, "o plano precisa de ao menos um módulo"}

  defp validar(modulos) do
    Enum.reduce_while(modulos, {:ok, []}, fn item, {:ok, acc} ->
      modulo = Map.get(item, "modulo")
      agentes = Map.get(item, "agentes")
      porque = Map.get(item, "porque", "")

      cond do
        not is_binary(modulo) or modulo == "" ->
          {:halt, {:error, "cada item precisa de `modulo` não vazio"}}

        not is_integer(agentes) or agentes < 1 ->
          {:halt,
           {:error,
            "módulo #{modulo}: `agentes` precisa ser inteiro >= 1 (recebido: #{inspect(agentes)})"}}

        true ->
          {:cont, {:ok, acc ++ [%{modulo: modulo, agentes: agentes, porque: porque}]}}
      end
    end)
  end

  # --- assess_implementability (ADR 0090) --------------------------------

  @spec spec_assess_implementability() :: map()
  # --- RN-699 (AT-362/AT-363): o que o Dev Lead LÊ ---

  @doc """
  Spec de `read_backlog`: leitura CONTIDA do backlog e do module_map vigente
  do PROJETO (ADR 0060, RN-164/165). Sem parâmetro — não há onde o modelo
  escreva o que quiser —, custo constante (duas leituras por chamada) e teto
  de linhas que diz o total real quando corta.
  """
  def spec_read_backlog do
    %{
      name: "read_backlog",
      description:
        "Lê as tarefas pendentes do backlog do projeto (task_id, título, história, " <>
          "módulos da história, módulo atual) e o module_map vigente. Use antes de " <>
          "propor o plano e sempre que o plano for recusado: só os task_id daqui são válidos.",
      parameters: %{"type" => "object", "properties" => %{}}
    }
  end

  @doc """
  RN-1006: o `create_task` do PO, com `module` obrigatório. O Dev Lead cria
  a tarefa de FUNDAÇÃO de um módulo ou a CORREÇÃO num módulo que já tem tarefa
  (RN-1517), numa história cujo `moduleIds` o contém; fora disso a recusa é
  nomeada.
  """
  def spec_create_task do
    base = Engine.Harness.Tools.CreateTask.spec()

    base
    |> put_in([:parameters, "properties", "module"], %{"type" => "string"})
    |> update_in([:parameters, "required"], &(&1 ++ ["module"]))
    |> Map.put(
      :description,
      "Cria a tarefa de FUNDAÇÃO de um módulo (a primeira dele) ou a CORREÇÃO num módulo que já " <>
        "tem tarefa, inclusive concluída (story_id, title, module). Tarefa concluída não se " <>
        "reabre: a correção é tarefa NOVA no mesmo módulo e entra na fila do dev dele. " <>
        "A história precisa listar o módulo em `moduleIds`."
    )
  end

  @spec run_create_task(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def run_create_task(%{"story_id" => story_id, "module" => modulo} = args, state) do
    ctx = %{project_id: state.project_id, session_id: state.session_id, agent_role: "dev_lead"}

    with {:ok, story_id} <-
           Engine.Harness.IdDoBacklog.resolver(state.project_id, :historia, story_id),
         {:ok, epicos} <- EngineApiClient.list_backlog(state.project_id),
         :ok <- historia_contem_modulo(epicos, story_id, modulo) do
      Engine.Harness.Tools.CreateTask.run(Map.put(args, "story_id", story_id), ctx)
    else
      {:error, _} = erro -> erro
      outro -> {:error, "não consegui ler o backlog para validar a história: #{inspect(outro)}"}
    end
  end

  def run_create_task(_args, _state),
    do: {:error, "create_task exige `story_id`, `title` e `module`"}

  @doc """
  AT-912 (RN-1087): `arquivar_tarefa`. Só tarefa `todo` que o próprio Dev Lead criou
  (a api confere e recusa com 409 nomeado), com motivo obrigatório. Nada é apagado.
  """
  def spec_arquivar_tarefa do
    %{
      name: "arquivar_tarefa",
      description:
        "Arquiva uma tarefa `todo` que VOCÊ criou (fundação repetida, criada por engano). " <>
          "Ela sai da fila, das dependências e da execução parada; nada é apagado. " <>
          "O motivo é obrigatório. Tarefa do PO ou já em execução é recusada.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "task_id" => %{"type" => "string"},
          "motivo" => %{"type" => "string"}
        },
        "required" => ["task_id", "motivo"]
      }
    }
  end

  @spec run_arquivar_tarefa(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def run_arquivar_tarefa(%{"task_id" => task_id, "motivo" => motivo}, state)
      when is_binary(task_id) and is_binary(motivo) do
    motivo = String.trim(motivo)

    with true <- motivo != "" or {:error, "arquivar_tarefa exige o `motivo`"},
         {:ok, task_id} <- Engine.Harness.IdDoBacklog.resolver(state.project_id, :tarefa, task_id) do
      case EngineApiClient.archive_task(state.project_id, state.session_id, task_id, motivo) do
        {:ok, _} ->
          {:ok, "tarefa #{task_id} arquivada (#{motivo}); saiu da fila e das dependências."}

        {:error, reason} ->
          {:error,
           "falha ao arquivar tarefa: #{Engine.Harness.Tools.RecusaDeHistoria.texto(reason)}"}
      end
    end
  end

  def run_arquivar_tarefa(_args, _state),
    do: {:error, "arquivar_tarefa exige `task_id` e `motivo`"}

  @doc """
  RN-1378 (AT-991): `levantar_tarefa`. Grava o levantamento da tarefa pela rota interna da
  api (AT-990); o plano com `depende_de` e o lote disjunto leem dele.
  """
  def spec_levantar_tarefa do
    lista = %{"type" => "array", "items" => %{"type" => "string"}}

    %{
      name: "levantar_tarefa",
      description:
        "Grava o levantamento de uma tarefa ANTES do plano: os arquivos que ela toca, o que " <>
          "expõe e o que consome de outras tarefas (as mesmas strings, de um lado e do outro), " <>
          "as dependências npm e o critério de aceite. A tarefa que cria uma tabela do contrato " <>
          "lista em `expoe` a linha `tabela <nome>` e, em `arquivos`, a migração dela. Falta contrato entre módulos: use " <>
          "`pedir_ao_arquiteto` antes de levantar.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "task_id" => %{"type" => "string"},
          "arquivos" => lista,
          "expoe" => lista,
          "consome" => lista,
          "dependencias_npm" => lista,
          "aceite" => %{"type" => "string"}
        },
        "required" => ["task_id", "arquivos", "expoe", "consome", "dependencias_npm", "aceite"]
      }
    }
  end

  @spec run_levantar_tarefa(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def run_levantar_tarefa(%{"task_id" => task_id} = args, state) when is_binary(task_id) do
    aceite = args |> Map.get("aceite", "") |> to_string() |> String.trim()
    listas = for k <- ~w(arquivos expoe consome dependencias_npm), do: Map.get(args, k)

    if aceite == "" or not Enum.all?(listas, &lista_de_texto?/1) do
      {:error,
       "levantar_tarefa exige `arquivos`, `expoe`, `consome`, `dependencias_npm` (listas de " <>
         "texto sem item vazio) e `aceite`"}
    else
      [arquivos, expoe, consome, npm] = listas

      with {:ok, uuid} <- Engine.Harness.IdDoBacklog.resolver(state.project_id, :tarefa, task_id) do
        corpo = %{
          arquivos: arquivos,
          expoe: expoe,
          consome: consome,
          dependenciasNpm: npm,
          aceite: aceite
        }

        case EngineApiClient.set_levantamento(state.project_id, state.session_id, uuid, corpo) do
          {:ok, _} ->
            {:ok, "tarefa #{uuid} levantada (#{length(arquivos)} arquivo(s))."}

          {:error, reason} ->
            {:error,
             "falha ao levantar tarefa: #{Engine.Harness.Tools.RecusaDeHistoria.texto(reason)}"}
        end
      end
    end
  end

  def run_levantar_tarefa(_args, _state), do: {:error, "levantar_tarefa exige `task_id`"}

  defp lista_de_texto?(l),
    do: is_list(l) and Enum.all?(l, &(is_binary(&1) and String.trim(&1) != ""))

  @doc """
  AT-906 (RN-1086): `procurar_tarefa`. Pede a um dev agent OCIOSO que tente o claim
  de novo, na hora. Quem decide é o status durável; fora de `idle` a recusa é nomeada.
  """
  def spec_procurar_tarefa do
    %{
      name: "procurar_tarefa",
      description:
        "Pede a um dev agent OCIOSO que procure tarefa de novo agora (use quando uma tarefa " <>
          "ficou liberada e o dev segue parado). Fora de `idle` nada acontece.",
      parameters: %{
        "type" => "object",
        "properties" => %{"agent_id" => %{"type" => "string"}},
        "required" => ["agent_id"]
      }
    }
  end

  @spec run_procurar_tarefa(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def run_procurar_tarefa(%{"agent_id" => agent_id}, state) when is_binary(agent_id) do
    case Engine.Dev.DevAgentState.get(state.project_id, agent_id) do
      nil ->
        {:error, "agente #{agent_id} não existe neste projeto"}

      %{status: "idle"} ->
        :ok = Engine.Dev.Wake.deliver(state.project_id, agent_id, {:wake, :became_claimable})
        {:ok, "ocioso: #{agent_id} está procurando tarefa."}

      %{status: status} ->
        {:ok, "#{agent_id} não está ocioso (status: #{status}); nada a procurar."}
    end
  end

  def run_procurar_tarefa(_args, _state), do: {:error, "procurar_tarefa exige `agent_id`"}

  defp historia_contem_modulo(epicos, story_id, modulo) do
    historia =
      Enum.find_value(epicos, fn e ->
        Enum.find(Map.get(e, "stories", []), &(Map.get(&1, "id") == story_id))
      end)

    if modulo in Map.get(historia || %{}, "moduleIds", []),
      do: :ok,
      else:
        {:error,
         "recusada: a história #{story_id} não lista o módulo `#{modulo}` em `moduleIds`. " <>
           "A tarefa só nasce numa história do próprio módulo."}
  end

  @doc "AT-909 (RN-1136): le o ultimo parecer de gate de uma tarefa."
  def spec_ler_parecer_da_tarefa do
    %{
      name: "ler_parecer_da_tarefa",
      description:
        "Le o ultimo parecer de gate (QA/SecOps) de uma tarefa: veredito, resumo, itens " <>
          "e melhorias. Use quando a execucao parar por ciclo de correcao esgotado.",
      parameters: %{
        "type" => "object",
        "properties" => %{"task_id" => %{"type" => "string"}},
        "required" => ["task_id"]
      }
    }
  end

  def run_ler_parecer_da_tarefa(%{"task_id" => task_id}, state) when is_binary(task_id) do
    case EngineApiClient.get_dev_context(state.project_id, state.session_id, task_id) do
      {:ok, %{"ultimoParecer" => %{} = p}} ->
        {:ok,
         "Gate #{p["gate"]}: #{p["veredito"]}\n#{p["resumo"]}\nItens:\n" <>
           Enum.map_join(List.wrap(p["itens"]), "\n", &"- #{&1}") <>
           "\nMelhorias:\n" <> Enum.map_join(List.wrap(p["melhorias"]), "\n", &"- #{&1}")}

      {:ok, _} ->
        {:ok, "(a tarefa nao tem parecer de gate)"}

      {:error, _} ->
        {:error, "nao consegui ler o parecer agora"}
    end
  end

  def run_ler_parecer_da_tarefa(_, _), do: {:error, "ler_parecer_da_tarefa exige `task_id`"}

  @doc "AT-996 (RN-1335): estado da tarefa/PR lido do backlog e do log da sessão, sem perguntar."
  def spec_ler_estado_da_pr do
    %{
      name: "ler_estado_da_pr",
      description:
        "Le o estado da tarefa e da sua PR: status, gate (awaiting_qa, awaiting_user...), " <>
          "bloqueio e se ha `git_merge` pendente de aprovacao na sessao. Use em vez de " <>
          "perguntar ao usuario se a tarefa foi concluida ou a PR mergeada.",
      parameters: %{
        "type" => "object",
        "properties" => %{"task_id" => %{"type" => "string"}},
        "required" => ["task_id"]
      }
    }
  end

  def run_ler_estado_da_pr(%{"task_id" => task_id}, state) when is_binary(task_id) do
    with {:ok, epicos} when is_list(epicos) <- EngineApiClient.list_backlog(state.project_id),
         %{} = t <- achar_tarefa(epicos, task_id) do
      {:ok,
       "tarefa #{t["id"]} (#{t["title"]}): status=#{t["status"]}, " <>
         "gate=#{gate_da_leitura(t)}, bloqueada=#{t["blocked"] == true}" <>
         if(t["blockedReason"], do: " (#{t["blockedReason"]})", else: "") <>
         ", arquivada=#{not is_nil(t["archivedAt"])}. " <> merge_pendente(state)}
    else
      nil -> {:ok, "(tarefa #{task_id} nao encontrada no backlog)"}
      _ -> {:error, "nao consegui ler o estado agora"}
    end
  end

  def run_ler_estado_da_pr(_, _), do: {:error, "ler_estado_da_pr exige `task_id`"}

  # RN-1505: tarefa `done` guarda `awaiting_user` por desenho (a web desenha a linha do tempo
  # dele); lida assim, parece merge pendente.
  defp gate_da_leitura(%{"status" => "done"}), do: "aprovado, PR mergeada"
  defp gate_da_leitura(t), do: t["gateStatus"] || "nenhum"

  defp achar_tarefa(epicos, task_id) do
    for(
      e <- epicos,
      h <- Map.get(e, "stories", []),
      t <- Map.get(h, "tasks", []),
      String.starts_with?(to_string(t["id"]), task_id),
      do: t
    )
    |> List.first()
  end

  defp merge_pendente(state) do
    tipos = ~w(proposed_action.created proposed_action.approved proposed_action.denied
               proposed_action.executed proposed_action.failed)

    case EngineApiClient.list_events(state.project_id, state.session_id,
           latest: true,
           limit: 200,
           types: tipos
         ) do
      {:ok, eventos} ->
        liquidadas =
          for %{"type" => t, "payload" => %{"actionId" => id}} <- eventos,
              t != "proposed_action.created",
              do: id

        n =
          Enum.count(eventos, fn
            %{
              "type" => "proposed_action.created",
              "payload" => %{"actionType" => "git_merge", "actionId" => id}
            } ->
              id not in liquidadas

            _ ->
              false
          end)

        "git_merge pendente na sessao: #{if n > 0, do: "sim (#{n})", else: "nao"}."

      _ ->
        "git_merge pendente: nao consegui ler."
    end
  end

  @doc "AT-996 (RN-1335): estado do plano de execucao (proposto/aprovado/recusado e ativacao)."
  def spec_ler_plano do
    %{
      name: "ler_plano",
      description:
        "Le o estado do plano de execucao: proposto, aprovado, recusado e se a execucao " <>
          "esta ativa. Use em vez de perguntar ao usuario se o plano foi aprovado.",
      parameters: %{"type" => "object", "properties" => %{}}
    }
  end

  def run_ler_plano(_args, state) do
    tipos = ~w(proposed_action.created proposed_action.approved proposed_action.denied
               proposed_action.executed proposed_action.failed execution.activated
               execution.plan_applied execution.plan_failed)

    case EngineApiClient.list_events(state.project_id, state.session_id,
           latest: true,
           limit: 200,
           types: tipos
         ) do
      {:ok, eventos} ->
        # RN-1505: `execution.activated` mora na sessão de EXECUÇÃO, não na do Dev Lead; aqui
        # entram o `plan_applied` (sessão do Dev Lead) e os dev agents do projeto.
        ativa =
          Enum.any?(eventos, &(&1["type"] in ~w(execution.activated execution.plan_applied))) or
            execucao_ativa?(state.project_id)

        estado =
          case ultimo_plano(eventos) do
            nil ->
              "nenhum plano proposto"

            {id, base} ->
              eventos |> Enum.reverse() |> Enum.find_value(base, &desfecho_do_plano(&1, id))
          end

        {:ok, "plano: #{estado}; execucao ativa: #{if ativa, do: "sim", else: "nao"}."}

      _ ->
        {:error, "nao consegui ler o plano agora"}
    end
  end

  defp ultimo_plano(eventos) do
    eventos
    |> Enum.filter(
      &match?(
        %{
          "type" => "proposed_action.created",
          "payload" => %{"actionType" => "propose_execution_plan"}
        },
        &1
      )
    )
    |> List.last()
    |> case do
      %{"payload" => %{"actionId" => id}} -> {id, "proposto, aguardando decisao"}
      _ -> nil
    end
  end

  defp desfecho_do_plano(
         %{"type" => "proposed_action.approved", "payload" => %{"actionId" => id}},
         id
       ),
       do: "aprovado"

  defp desfecho_do_plano(
         %{"type" => "proposed_action.executed", "payload" => %{"actionId" => id}},
         id
       ),
       do: "aprovado e aplicado"

  defp desfecho_do_plano(
         %{"type" => "proposed_action.denied", "payload" => %{"actionId" => id}},
         id
       ),
       do: "recusado"

  defp desfecho_do_plano(
         %{"type" => "proposed_action.failed", "payload" => %{"actionId" => id}},
         id
       ),
       do: "falhou ao aplicar"

  defp desfecho_do_plano(%{"type" => "execution.plan_applied"}, _), do: "aprovado e aplicado"

  defp desfecho_do_plano(%{"type" => "execution.plan_failed", "payload" => p}, _) do
    motivo = if is_map(p), do: p["motivo"] || p["reason"] || p["error"], else: nil
    "falhou ao aplicar" <> if(is_binary(motivo), do: ": #{motivo}", else: "")
  end

  defp desfecho_do_plano(_, _), do: nil

  @spec run_read_backlog(map()) :: {:ok, String.t()}
  def run_read_backlog(state) do
    {:ok,
     "MÓDULOS (module_map vigente):\n" <>
       module_map_vigente(state.project_id, state.session_id) <>
       tarefas_do_backlog(state.project_id)}
  end

  @doc """
  O module_map VIGENTE do projeto, em texto. Lido pela MESMA rota que o
  AppSec usa (`get_infra_context`, `findCurrent` na api) — e não por evento
  da sessão: o kickoff procurava `architecture.module_map_created`, tipo que
  nenhum código emite (AT-362).
  """
  @spec module_map_vigente(String.t(), String.t()) :: String.t()
  def module_map_vigente(project_id, session_id) do
    case EngineApiClient.get_infra_context(project_id, session_id) do
      {:ok, %{"moduleMap" => %{"modules" => mods}}} when is_list(mods) and mods != [] ->
        Enum.map_join(mods, "\n", fn m ->
          "- #{Map.get(m, "name")} (#{Map.get(m, "stack", "?")}): #{Map.get(m, "responsibility", "")}" <>
            " | dependsOn: #{depende_de(m)}"
        end)

      {:ok, _} ->
        "(sem module_map vigente — o Arquiteto ainda não gravou um)"

      {:error, _} ->
        "(não consegui ler o module_map agora — tente `read_backlog` de novo)"
    end
  end

  defp depende_de(m) do
    case Map.get(m, "dependsOn", []) do
      [_ | _] = deps -> Enum.join(deps, ", ")
      _ -> "(nenhum)"
    end
  end

  # AT-274 (RN-678): o plano atribui o MÓDULO de cada tarefa, então o Dev Lead
  # precisa dos `task_id`s — e do backlog do PROJETO, não só do que nasceu
  # nesta sessão. Pela MESMA rota da `listar_backlog` do PO; tarefa `done` fica
  # de fora. Falha vira uma linha dita, nunca kickoff perdido.
  @max_tarefas 200

  @doc false
  @spec tarefas_do_backlog(String.t()) :: String.t()
  def tarefas_do_backlog(project_id) do
    case EngineApiClient.list_backlog(project_id) do
      {:ok, epicos} when is_list(epicos) ->
        linhas =
          for epico <- epicos,
              historia <- Map.get(epico, "stories", []),
              tarefa <- Map.get(historia, "tasks", []),
              Map.get(tarefa, "status") != "done" do
            "- task_id=#{Map.get(tarefa, "id")} | #{Map.get(tarefa, "title")} " <>
              "| história: #{Map.get(historia, "title")} " <>
              "(módulos da história: #{Enum.join(Map.get(historia, "moduleIds", []), ", ")})" <>
              modulo_atual(tarefa) <> bloqueio(tarefa)
          end

        mostradas = Enum.take(linhas, @max_tarefas)
        entregues = modulos_entregues(epicos)

        corte =
          case length(linhas) - length(mostradas) do
            0 -> ""
            n -> "\n(+ #{n} tarefa(s) não listada(s) — o total real é #{length(linhas)})"
          end

        """

        TAREFAS PENDENTES (atribua CADA UMA a um módulo do module_map em `tarefas`
        — só o dev agent daquele módulo vai pegá-la):
        #{if mostradas == [], do: "(nenhuma tarefa pendente)", else: Enum.join(mostradas, "\n")}#{corte}#{entregues}
        """

      _ ->
        "\n\n(não consegui listar as tarefas do backlog agora — chame `read_backlog` de novo; " <>
          "não invente task_id.)"
    end
  end

  # RN-1131 (AT-910): módulo cujas tarefas estão todas `done` aparece como
  # ENTREGUE (sem listar as tarefas), para o Dev Lead não recriar fundação.
  defp modulos_entregues(epicos) do
    por_modulo =
      for e <- epicos,
          h <- Map.get(e, "stories", []),
          t <- Map.get(h, "tasks", []),
          m = Map.get(t, "module"),
          is_binary(m) and m != "",
          reduce: %{} do
        acc -> Map.update(acc, m, [t], &[t | &1])
      end

    for {m, ts} <- Enum.sort(por_modulo), Enum.all?(ts, &(Map.get(&1, "status") == "done")) do
      "\nENTREGUE: módulo #{m} (#{length(ts)} tarefa(s) done, na main)"
    end
    |> Enum.join()
  end

  # RN-887 (AT-536): o bloqueio é ortogonal ao `status` — a bloqueada segue
  # `todo`, então a linha diz que está BLOQUEADA, e por quê.
  defp bloqueio(%{"blocked" => true} = tarefa) do
    motivo =
      case Map.get(tarefa, "blockedReason") do
        m when is_binary(m) and m != "" -> String.slice(m, 0, 120)
        _ -> "sem motivo registrado"
      end

    " | BLOQUEADA: #{motivo}"
  end

  defp bloqueio(_), do: ""

  defp modulo_atual(%{"module" => m}) when is_binary(m) and m != "",
    do: " [módulo atual: #{m}]"

  defp modulo_atual(_tarefa), do: ""

  def spec_assess_implementability do
    %{
      name: "assess_implementability",
      description:
        "Avalia se uma story do backlog é IMPLEMENTÁVEL, a partir da própria " <>
          "história (RF, RNF, definition of done) e do module_map vigente que " <>
          "você já tem no contexto — o plano de teste só existe DEPOIS da " <>
          "entrega do dev, não é insumo daqui. Propõe o parecer de " <>
          "implementabilidade: é uma decisão real, que o usuário aprova ou " <>
          "recusa em Aprovações (gate `implementavel`). Se a story ainda não " <>
          "tem threat model, esta chamada também pede o de AppSec — que corre " <>
          "em paralelo e não atrasa o parecer.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "storyId" => %{"type" => "string"},
          "parecer" => %{
            "type" => "string",
            "enum" => ["implementavel", "inviavel"]
          },
          "justificativa" => %{
            "type" => "string",
            "description" => "o que na story (RF/RNF/DoD) e no module_map sustenta o parecer"
          }
        },
        "required" => ["storyId", "parecer", "justificativa"]
      }
    }
  end

  @spec run_assessment(map(), map()) ::
          {:ok, String.t()} | {:pending, String.t()} | {:error, String.t()}
  def run_assessment(
        %{"storyId" => story_id, "parecer" => parecer, "justificativa" => justificativa},
        state
      )
      when parecer in ["implementavel", "inviavel"] do
    # RN-721: aceita o prefixo (>= 8 hex) que o modelo copia encurtado.
    case IdDoBacklog.resolver(state.project_id, :historia, story_id) do
      {:ok, uuid} -> avaliar(uuid, parecer, justificativa, state)
      erro -> erro
    end
  end

  def run_assessment(_args, _state),
    do:
      {:error,
       "assess_implementability exige storyId, parecer (implementavel|inviavel) e justificativa"}

  defp avaliar(story_id, parecer, justificativa, state) do
    # A CAUDA, com o mesmo teto da reidratação (RN-580, ADR 0060): sem
    # `latest`, a api devolve os PRIMEIROS 200 e numa sessão longa o threat
    # model recém-emitido ficava de fora.
    case EngineApiClient.list_events(state.project_id, state.session_id,
           latest: true,
           limit: Reidratacao.teto()
         ) do
      {:ok, eventos} ->
        # Em PARALELO, e sem que o parecer dependa disso — ver a seção
        # "O appsec dispara junto" no moduledoc. É a ÚNICA razão de ler o
        # histórico aqui desde o ADR 0192: o plano de teste deixou de ser
        # pré-requisito.
        disparar_appsec_se_preciso(state, story_id, eventos)
        propor_parecer(state, story_id, parecer, justificativa)

      {:error, reason} ->
        {:error, "não consegui ler o histórico da sessão: #{inspect(reason)}"}
    end
  end

  # A leitura do histórico é UMA por chamada de `run_assessment/2` (ADR 0060:
  # nada de duas leituras na mesma invocação), e serve só à guarda do appsec.
  #
  # RN-539: o appsec (`Engine.Gates.SecOpsAgentServer.run_design/2`) era
  # ACIONÁVEL e não tinha chamador de produção nenhum — `docs/fluxo.yml`
  # declarava a lacuna e nomeava ESTE ponto como o gatilho natural.
  #
  # A guarda de idempotência não é zelo: o modelo pode chamar
  # `assess_implementability` de novo para a mesma story (reavaliar, ou
  # repetir depois de um erro), e sem ela cada rechamada dispararia outra
  # rodada de LLM do appsec e mais três handoffs (RN-361) sobre a MESMA
  # story. A pergunta aqui é EXISTE, não QUAL.
  #
  # Limite declarado: `artifact.threat_model` é emitido na sessão da STORY
  # (`emit_threat_model/3` lê `story["sessionId"]`), enquanto esta leitura é
  # da sessão do DEV LEAD. No caminho comum são a mesma sessão — o Dev Lead
  # avalia stories do backlog que a própria sessão de execução criou. Não
  # sendo, a guarda não enxerga o threat model e o appsec roda de novo:
  # custo de uma rodada de LLM repetida, nunca dado errado (o artefato é
  # append-only, e quem consome é o handoff). Fechar isso exigiria a api
  # aceitar uma busca de artefato por story ATRAVÉS de sessões, que hoje não
  # existe — fora do escopo desta entrega.
  defp disparar_appsec_se_preciso(state, story_id, eventos) do
    unless Enum.any?(eventos, &threat_model_da_story?(&1, story_id)) do
      Dispatcher.run_appsec_design(state.project_id, story_id)
    end

    :ok
  end

  defp threat_model_da_story?(
         %{"type" => "artifact.threat_model", "payload" => payload},
         story_id
       ),
       do: Map.get(payload, "storyId") == story_id

  defp threat_model_da_story?(_evento, _story_id), do: false

  # ADR 0192: sem `planoDeTeste`/`criteriosExecutaveis` — o plano nasce
  # depois da entrega e não existe aqui. O que o usuário lê para decidir é a
  # justificativa do Dev Lead sobre a história e o `module_map`.
  defp propor_parecer(state, story_id, parecer, justificativa) do
    actor = %{kind: "agent", id: "dev-lead"}

    payload = %{
      storyId: story_id,
      parecer: parecer,
      justificativa: justificativa
    }

    case EngineApiClient.propose_action(
           state.project_id,
           state.session_id,
           "assess_implementability",
           actor,
           payload
         ) do
      {:ok, action} ->
        classificar_parecer(Map.get(action, "status"), Map.get(action, "id"), parecer, story_id)

      {:error, reason} ->
        {:error, "não consegui propor o parecer de implementabilidade: #{inspect(reason)}"}
    end
  end

  # Mesmo raciocínio de `classificar/4`, acima: `assess_implementability`
  # também não tem execute-* pipeline própria (não há efeito a aplicar —
  # o parecer é registro para o usuário decidir). Os três contam sucesso.
  defp classificar_parecer(status, _action_id, parecer, story_id)
       when status in ["executed", "auto_approved", "approved"] do
    {:ok,
     "parecer (#{parecer}) registrado para a story #{story_id}. " <>
       "O usuário decide em Aprovações."}
  end

  defp classificar_parecer("pending", action_id, _parecer, _story_id)
       when is_binary(action_id) do
    {:pending, action_id}
  end

  defp classificar_parecer(status, _action_id, _parecer, _story_id) do
    {:error, "o parecer não foi registrado (status inesperado: #{inspect(status)})"}
  end

  @doc """
  O resumo CALCULADO pela api do plano aplicado (AT-381, RN-709): tarefas por
  módulo e os módulos sem tarefa, que não ganharam agente. É o que o Dev Lead
  cita ao narrar, em vez de recontar de memória. Vazio quando a api não o
  mandou (plano sem `tarefas`).
  """
  def resumo_do_plano(%{"tarefasPorModulo" => por_modulo} = exec)
      when is_map(por_modulo) and map_size(por_modulo) > 0 do
    contagem =
      por_modulo
      |> Enum.sort()
      |> Enum.map_join(" · ", fn {m, n} -> "#{m} #{n}" end)

    sem =
      case Map.get(exec, "modulosSemTarefa") do
        [_ | _] = lista -> " Sem tarefa, sem agente: #{Enum.join(lista, ", ")}."
        _ -> ""
      end

    " Tarefas por módulo (cite estes números): #{contagem}." <> sem <> segundo_dev(exec)
  end

  def resumo_do_plano(_), do: ""

  # RN-1417 (AT-992): o segundo dev do lote disjunto sobe pelo aceite da api, que
  # pode recusar (teto da área); o Dev Lead narra o que subiu e o que foi recusado.
  defp segundo_dev(exec) do
    subiu =
      case Map.get(exec, "segundoDev") do
        [_ | _] = l -> " Segundo dev subiu em: #{Enum.join(l, ", ")}."
        _ -> ""
      end

    recusado =
      case Map.get(exec, "segundoDevRecusado") do
        %{} = m when map_size(m) > 0 ->
          " Segundo dev RECUSADO (o módulo segue com um agente): " <>
            Enum.map_join(Enum.sort(m), "; ", fn {mod, motivo} -> "#{mod}: #{motivo}" end) <> "."

        _ ->
          ""
      end

    subiu <> recusado
  end
end
