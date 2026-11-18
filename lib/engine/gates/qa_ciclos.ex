defmodule Engine.Gates.QaCiclos do
  @moduledoc """
  AT-989 (RN-1401, ADR 0038 revisto): o QA julga as PRs EM PARALELO. Um destes
  por projeto (`Engine.Gates.Registry`, chave `{project_id, "qa"}` — a MESMA de
  antes, então o `Dispatcher`, o `GateRescuer` e o encerramento da sessão não
  mudam) ABRE UM `Engine.Gates.QaLeadServer` por tarefa e não roda ciclo nenhum
  por conta própria. A fila única do Lead serial fazia a 2ª PR esperar a 1ª
  inteira (plano, ambiente, automação).

  RN-1402: no máximo `teto/1` ciclos RODANDO ao mesmo tempo por projeto — o
  número de dev agents ativos (as PRs que podem chegar juntas), limitado por
  `:qa_ciclos_maximo` (15, o teto de agentes). Ciclo SUSPENSO esperando decisão
  humana não ocupa vaga (como o Lead serial, que ficava livre nessa espera). A
  N+1ª tarefa espera na fila e entra quando uma vaga abre.

  Mantém aqui o que sobrevive ao ciclo: a contagem de retomadas do gate
  (RN-1349) e a varredura de pedidos obsoletos (RN-806).
  """

  use GenServer, restart: :temporary

  require Logger

  def start_link(project_id),
    do:
      GenServer.start_link(__MODULE__, project_id,
        name: Engine.Gates.QaLeadServer.via(project_id)
      )

  @doc "Ciclos simultâneos permitidos ao projeto."
  def teto(project_id) do
    maximo = Application.get_env(:engine, :qa_ciclos_maximo, 15)

    case Application.get_env(:engine, :qa_ciclos_por_projeto) do
      n when is_integer(n) and n > 0 ->
        min(n, maximo)

      _ ->
        devs =
          Engine.Dev.Registry
          |> Registry.select([{{{:"$1", :"$2"}, :_, :_}, [{:==, :"$1", project_id}], [:"$2"]}])
          |> Enum.count(&(String.starts_with?(&1, "dev-") and &1 != "dev-lead"))

        devs |> max(1) |> min(maximo)
    end
  end

  @impl true
  def init(project_id) do
    Process.flag(:trap_exit, true)
    {:ok, %{project_id: project_id, ciclos: %{}, fila: [], retomadas: %{}}}
  end

  # RN-722: "em voo" = tem ciclo (rodando ou suspenso) ou espera vaga.
  @impl true
  def handle_call({:em_voo?, task_id}, _from, state),
    do: {:reply, Map.has_key?(state.ciclos, task_id) or task_id in state.fila, state}

  @impl true
  def handle_cast({:run, task_id}, state) do
    if Map.has_key?(state.ciclos, task_id) or task_id in state.fila do
      Logger.info("QaLead: ciclo qa da task #{task_id} já em voo — pedido repetido ignorado")
      {:noreply, state}
    else
      {:noreply, abrir_vagas(%{state | fila: state.fila ++ [task_id]})}
    end
  end

  @impl true
  def handle_info({:ciclo_suspenso, task_id}, state),
    do: {:noreply, abrir_vagas(put_in(state, [:ciclos, task_id, :estado], :suspenso))}

  def handle_info({:ciclo_terminado, task_id, feitas}, state) do
    retomadas =
      if feitas,
        do: Map.put(state.retomadas, task_id, feitas),
        else: Map.delete(state.retomadas, task_id)

    state = %{state | ciclos: Map.delete(state.ciclos, task_id), retomadas: retomadas}
    {:noreply, state |> descartar_pedidos_obsoletos(task_id) |> abrir_vagas()}
  end

  # Ciclo que morreu sem avisar: libera a vaga. A linha durável (`GateState`)
  # segue "in_progress" e o `GateRescuer` o reabre.
  def handle_info({:EXIT, pid, _motivo}, state) do
    case Enum.find(state.ciclos, fn {_, c} -> c.pid == pid end) do
      {task_id, _} ->
        {:noreply, abrir_vagas(%{state | ciclos: Map.delete(state.ciclos, task_id)})}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp abrir_vagas(%{fila: [task_id | resto]} = state) do
    if rodando(state) < teto(state.project_id) do
      feitas = Map.get(state.retomadas, task_id, 0)
      {:ok, pid} = ciclo_server().start_link({state.project_id, task_id, feitas, self()})
      ciclos = Map.put(state.ciclos, task_id, %{pid: pid, estado: :rodando})
      abrir_vagas(%{state | fila: resto, ciclos: ciclos})
    else
      state
    end
  end

  defp abrir_vagas(state), do: state

  # Trocável só nos testes do teto/paralelismo.
  defp ciclo_server, do: Application.get_env(:engine, :qa_ciclo_server, Engine.Gates.QaLeadServer)

  defp rodando(state), do: Enum.count(state.ciclos, fn {_, c} -> c.estado == :rodando end)

  # RN-806: pedido que esperava na caixa foi feito ANTES do veredito.
  defp descartar_pedidos_obsoletos(state, task_id) do
    receive do
      {:"$gen_cast", {:run, ^task_id}} ->
        Logger.info(
          "QaLead: pedido de ciclo qa da task #{task_id} anterior ao veredito descartado (RN-806)"
        )

        descartar_pedidos_obsoletos(state, task_id)
    after
      0 -> state
    end
  end
end
