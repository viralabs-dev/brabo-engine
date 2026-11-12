defmodule Engine.Agents.DevLeadProcurarTarefaTest do
  @moduledoc "AT-906 (RN-1086): `procurar_tarefa` acorda só o dev ocioso."
  use Engine.DataCase, async: false

  alias Engine.Agents.DevLeadTools
  alias Engine.Dev.{DevAgentState, Wake}

  test "idle recebe o wake; outro status e inexistente são ditos" do
    state = %{project_id: Ecto.UUID.generate(), session_id: "s1"}

    for {id, status} <- [{"dev-a", "idle"}, {"dev-b", "working"}] do
      DevAgentState.upsert!(%{
        project_id: state.project_id,
        agent_id: id,
        module: id,
        session_id: "s1",
        status: status
      })

      Wake.subscribe(state.project_id, id)
    end

    assert {:ok, "ocioso:" <> _} =
             DevLeadTools.run_procurar_tarefa(%{"agent_id" => "dev-a"}, state)

    assert_received {:wake, :became_claimable}

    assert {:ok, msg} = DevLeadTools.run_procurar_tarefa(%{"agent_id" => "dev-b"}, state)
    assert msg =~ "não está ocioso"
    refute_received {:wake, _}

    assert {:error, _} = DevLeadTools.run_procurar_tarefa(%{"agent_id" => "dev-z"}, state)
  end
end
