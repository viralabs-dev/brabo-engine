defmodule Engine.Workers.ReiniciarAppWorker do
  @moduledoc """
  RN-1028 (AT-617): depois que a pasta do projeto avançou até a `main`, o processo
  do app declarado (`run.app`) é reiniciado no lugar pela api. O job é único por
  projeto e atrasado (`@atraso_s`), então merges em sequência viram UM reinício,
  feito com a pasta já na última `main`.

  O desfecho vai para a linha do tempo da sessão que agendou, sem trecho de log
  (o comando do app pode carregar segredo): `app.restarted`, `app.restart_failed`
  ou `app.restart_skipped`. Falha só avisa; a pasta nunca volta.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Engine.Sessions.EngineApiClient

  @atraso_s 20

  @doc "Agenda o reinício de `project_id`; já agendado dentro da janela, não duplica."
  def agendar(project_id, session_id) do
    %{"projectId" => project_id, "sessionId" => session_id}
    |> new(
      schedule_in: @atraso_s,
      unique: [period: 60, keys: [:projectId], states: [:available, :scheduled]]
    )
    |> Oban.insert()
  end

  @impl true
  def perform(%Oban.Job{args: %{"projectId" => pid, "sessionId" => sid}}) do
    case EngineApiClient.reiniciar_app(pid) do
      {:ok, %{"reiniciou" => true}} ->
        evento(pid, sid, "app.restarted", %{})

      {:ok, %{"reiniciou" => false, "motivo" => "sem_app"}} ->
        evento(pid, sid, "app.restart_skipped", %{motivo: "sem_app"})

      {:ok, %{"reiniciou" => false} = r} ->
        evento(pid, sid, "app.restart_failed", falha(r))

      {:error, _} ->
        evento(pid, sid, "app.restart_failed", %{motivo: "falha_na_chamada"})
    end

    :ok
  end

  @motivos ~w(sem_container tempo_esgotado falha_no_exec app_saiu)

  # Allowlist: só motivo conhecido e exitCode saem; nenhum texto livre da resposta.
  defp falha(r) do
    %{motivo: if(r["motivo"] in @motivos, do: r["motivo"], else: "desconhecido")}
    |> then(&if is_integer(r["exitCode"]), do: Map.put(&1, :exitCode, r["exitCode"]), else: &1)
  end

  defp evento(pid, sid, type, payload) do
    EngineApiClient.append_event(pid, sid, %{
      type: type,
      actorKind: "system",
      actorId: "engine",
      payload: payload
    })
  end
end
