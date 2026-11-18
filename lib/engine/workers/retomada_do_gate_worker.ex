defmodule Engine.Workers.RetomadaDoGateWorker do
  @moduledoc """
  AT-984 (RN-1347): a retomada automática do GATE de QA quando o subagente
  parou por falha PASSAGEIRA do provedor (`Engine.Gates.OrigemDoErro.passageira?/1`).
  Mesmas esperas e mesmo teto da RN-864 (1, 3 e 10 min, até 3 retomadas): em
  vez de bloquear a tarefa (o que mandava o bloqueio ao dev), o gate roda de
  novo pelo `Dispatcher.run_qa/2`. É seguro repetir: a api recusa veredito em
  duplicata (ver `Engine.Gates.GateRescuer`).

  O contador mora no estado do `QaLeadServer`, só em memória: reiniciar o
  engine o zera, como na RN-864.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Engine.Gates.Dispatcher

  # shortcut: cópia dos atrasos do RetomadaDeTarefaWorker (RN-864); unificar se um dia mudarem.
  @atrasos_em_minutos [1, 3, 10]

  @doc "Quantas retomadas o gate de uma task pode ter."
  def teto, do: length(@atrasos_em_minutos)

  @doc "Agenda a retomada `feitas + 1`: `{:ok, minutos}` ou `:esgotado`."
  def agendar(project_id, task_id, feitas) when feitas < length(@atrasos_em_minutos) do
    minutos = Enum.at(@atrasos_em_minutos, feitas)

    %{"projectId" => project_id, "taskId" => task_id, "tentativa" => feitas + 1}
    |> new(schedule_in: minutos * 60)
    |> Oban.insert()

    {:ok, minutos}
  end

  def agendar(_project_id, _task_id, _feitas), do: :esgotado

  @impl true
  def perform(%Oban.Job{args: %{"projectId" => project_id, "taskId" => task_id}}) do
    :ok = Dispatcher.run_qa(project_id, task_id)
  end

  def perform(%Oban.Job{}), do: :ok
end
