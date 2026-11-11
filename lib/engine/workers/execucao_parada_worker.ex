defmodule Engine.Workers.ExecucaoParadaWorker do
  @moduledoc """
  AT-800 (RN-1059): avisa a sessão quando a execução inteira parou atrás de uma
  tarefa bloqueada ou de um agente travado.

  Cada dev agent decide sozinho (`dev.idle`, `dev.idle_tripped`,
  `dev.credit_exhausted`), e ninguém olhava o conjunto: no TP-01 27ª foram 57 min
  parados sem aviso. `AgentIo` enfileira este job (um por sessão, 5 s depois, para
  juntar os `dev.idle` da mesma rajada) e o `perform` decide:

    1. todo dev agent da sessão está `idle` ou `idle_tripped`;
    2. há tarefa pendente (`status != done`);
    3. há motivo: tarefa `blocked` ou agente `idle_tripped`.

  Então grava `execution.stalled` (contrato com a web) e entrega
  `{:execucao_parada, payload}` ao Dev Lead pelo `Engine.Dev.Wake`. Não repete
  enquanto o último evento de movimento da sessão for um `execution.stalled`
  com os mesmos motivos. PR esperando merge, sem bloqueio nem disjuntor, não
  conta (AT-810).

  AT-906 (RN-1086): antes de avaliar, entrega `{:wake, :became_claimable}` a todo
  agente `idle` da sessão e espera `espera_do_claim_ms/0` para o claim assentar; re-tentar
  é inofensivo, porque quem decide é o guard em processo do agente. Tarefa arquivada
  (`archivedAt`, AT-912) não é pendência. AT-913 (RN-1088): a tarefa bloqueada do módulo Y
  cujo motivo cita um módulo X que depende de Y (direta ou transitivamente) vai em
  `ciclosDeDependencia`.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [period: 30, keys: [:projectId, :sessionId], states: :incomplete]

  alias Engine.Dev.{DevAgentState, Wake}
  alias Engine.SessionEvents.Event
  alias Engine.Sessions.EngineApiClient

  require Logger

  @espera 5
  @teto_tarefas 10
  @movimento ~w(execution.stalled dev.working dev.rearmed dev.wake_requested backlog.task_unblocked)

  @doc "Enfileira a checagem (nunca derruba o agente que chama)."
  def agendar(project_id, session_id) when is_binary(project_id) and is_binary(session_id) do
    %{"projectId" => project_id, "sessionId" => session_id}
    |> new(schedule_in: @espera)
    |> Oban.insert()
  rescue
    e -> Logger.warning("ExecucaoParadaWorker: não enfileirou: #{Exception.message(e)}")
  catch
    :exit, _ -> :ok
  end

  def agendar(_project_id, _session_id), do: :ok

  @impl true
  def perform(%Oban.Job{args: %{"projectId" => project_id, "sessionId" => session_id}}) do
    agentes =
      project_id |> DevAgentState.list_by_project() |> Enum.filter(&(&1.session_id == session_id))

    with true <- agentes != [] and Enum.all?(agentes, &(&1.status in ~w(idle idle_tripped))),
         :ok <- reprocurar(project_id, agentes),
         agentes =
           project_id
           |> DevAgentState.list_by_project()
           |> Enum.filter(&(&1.session_id == session_id)),
         true <- Enum.all?(agentes, &(&1.status in ~w(idle idle_tripped))),
         {:ok, epicos} when is_list(epicos) <- EngineApiClient.list_backlog(project_id),
         tarefas = pendentes(epicos),
         true <- tarefas != [] do
      travados =
        for a <- agentes, a.status == "idle_tripped", do: %{agentId: a.agent_id, module: a.module}

      bloqueadas =
        for t <- tarefas, Map.get(t, "blocked") == true do
          %{
            taskId: Map.get(t, "id"),
            title: Map.get(t, "title"),
            module: Map.get(t, "module"),
            reason: t |> Map.get("blockedReason") |> to_string() |> String.slice(0, 200)
          }
        end

      if travados != [] or bloqueadas != [] do
        payload = %{
          agentesOciosos: for(a <- agentes, a.status == "idle", do: a.agent_id),
          agentesTravados: travados,
          tarefasBloqueadas: Enum.take(bloqueadas, @teto_tarefas),
          tarefasPendentes: length(tarefas)
        }

        payload =
          case ciclos(project_id, session_id, bloqueadas) do
            [] -> payload
            ciclos -> Map.put(payload, :ciclosDeDependencia, ciclos)
          end

        avisar(project_id, session_id, payload)
      end
    end

    :ok
  rescue
    e ->
      Logger.warning("ExecucaoParadaWorker: leitura falhou: #{Exception.message(e)}")
      :ok
  end

  def perform(%Oban.Job{}), do: :ok

  defp pendentes(epicos) do
    for epico <- epicos,
        historia <- Map.get(epico, "stories", []),
        tarefa <- Map.get(historia, "tasks", []),
        Map.get(tarefa, "status") != "done",
        is_nil(Map.get(tarefa, "archivedAt")),
        do: tarefa
  end

  @doc "Intervalo que o worker espera depois de acordar os ociosos, para o claim assentar."
  def espera_do_claim_ms, do: Application.get_env(:engine, :espera_do_claim_ms, 3_000)

  defp reprocurar(project_id, agentes) do
    ociosos = for a <- agentes, a.status == "idle", do: a.agent_id
    Enum.each(ociosos, &Wake.deliver(project_id, &1, {:wake, :became_claimable}))
    if ociosos != [], do: Process.sleep(espera_do_claim_ms())
    :ok
  end

  @doc """
  AT-913 (RN-1088): ciclos entre o bloqueio e o `dependsOn`. Puro sobre o mapa: `modulos` é a
  lista `[%{"name" =>, "dependsOn" => [..]}]` do module_map vigente e `bloqueadas` as tarefas
  com `module` e `reason`. Devolve `[%{taskId, modulo: Y, esperaPor: X}]`.
  """
  def ciclos_de_dependencia(modulos, bloqueadas) do
    deps = Map.new(modulos, &{Map.get(&1, "name"), Map.get(&1, "dependsOn") || []})

    for t <- bloqueadas,
        y = Map.get(t, :module),
        is_binary(y),
        x <- Map.keys(deps),
        x != y,
        depende?(deps, x, y, MapSet.new()),
        cita?(Map.get(t, :reason), x),
        do: %{taskId: t.taskId, modulo: y, esperaPor: x}
  end

  defp depende?(deps, x, y, visto) do
    diretas = Map.get(deps, x, [])

    y in diretas or
      Enum.any?(diretas, fn d ->
        not MapSet.member?(visto, d) and depende?(deps, d, y, MapSet.put(visto, d))
      end)
  end

  # `modules/X`, `dev-X` ou `X` com borda; `x-y` não cita `x`.
  defp cita?(reason, modulo) do
    Regex.match?(~r/(?<![\w-])(?:dev-)?#{Regex.escape(modulo)}(?![\w-])/i, to_string(reason))
  end

  defp ciclos(_project_id, _session_id, []), do: []

  defp ciclos(project_id, session_id, bloqueadas) do
    case EngineApiClient.get_infra_context(project_id, session_id) do
      {:ok, %{"moduleMap" => %{"modules" => mods}}} when is_list(mods) ->
        ciclos_de_dependencia(mods, bloqueadas)

      _ ->
        []
    end
  end

  defp avisar(project_id, session_id, payload) do
    if repetido?(session_id, payload) do
      :ok
    else
      evento = %{
        type: "execution.stalled",
        actorKind: "system",
        actorId: "execucao",
        payload: payload
      }

      case EngineApiClient.append_event(project_id, session_id, evento) do
        :ok -> Wake.deliver(project_id, "dev-lead", {:execucao_parada, payload})
        erro -> Logger.warning("ExecucaoParadaWorker: append falhou: #{inspect(erro)}")
      end
    end
  end

  # Repetido = o último evento de movimento da sessão é um `execution.stalled` com os mesmos motivos.
  defp repetido?(session_id, payload) do
    session_id
    |> Event.list_recent(200)
    |> Enum.filter(&(&1.type in @movimento))
    |> List.last()
    |> case do
      %{type: "execution.stalled", payload: p} -> motivos(p) == motivos(payload)
      _ -> false
    end
  end

  defp motivos(p) do
    tarefas = Map.get(p, "tarefasBloqueadas") || Map.get(p, :tarefasBloqueadas) || []
    agentes = Map.get(p, "agentesTravados") || Map.get(p, :agentesTravados) || []

    {tarefas |> Enum.map(&(Map.get(&1, "taskId") || Map.get(&1, :taskId))) |> Enum.sort(),
     agentes |> Enum.map(&(Map.get(&1, "agentId") || Map.get(&1, :agentId))) |> Enum.sort()}
  end
end
