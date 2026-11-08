defmodule Engine.Harness.Tools.UpdateTaskTest do
  @moduledoc "RN-1068: o PO e o Dev Lead corrigem a tarefa `todo`."

  use ExUnit.Case, async: false

  alias Engine.Agents.{GravadoNoTurno, TextoDoTurno}
  alias Engine.Harness.IdiomaDaResposta
  alias Engine.Harness.Tools.UpdateTask

  @uuid "863d42c2-4f5f-45ad-a35a-6891d40211be"

  setup do
    Application.put_env(:engine, :engine_api_client, Engine.Sessions.FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())
    on_exit(fn -> Application.delete_env(:engine, :test_pid) end)
    %{ctx: %{project_id: "p1", session_id: "s1", agent: "po"}}
  end

  test "manda só os campos informados, com o agentId do PO", %{ctx: ctx} do
    assert {:ok, texto} = UpdateTask.run(%{"task_id" => @uuid, "title" => "Agenda"}, ctx)
    assert texto =~ "tarefa corrigida: id=#{@uuid}"
    assert_received {:task_updated, @uuid, %{title: "Agenda", agentId: "po"} = campos}
    refute Map.has_key?(campos, :description)
  end

  test "o Dev Lead manda agentId dev-lead", %{ctx: ctx} do
    UpdateTask.run(%{"task_id" => @uuid, "description" => "x"}, %{ctx | agent: "dev-lead"})
    assert_received {:task_updated, @uuid, %{agentId: "dev-lead"}}
  end

  test "sem title nem description não chama a api", %{ctx: ctx} do
    assert {:error, texto} = UpdateTask.run(%{"task_id" => @uuid}, ctx)
    assert texto =~ "exige `title` ou `description`"
    refute_received {:task_updated, _, _}
  end

  test "o prefixo do id é resolvido para o uuid", %{ctx: ctx} do
    Process.put(:fake_backlog, [%{"stories" => [%{"tasks" => [%{"id" => @uuid}]}]}])
    assert {:ok, _} = UpdateTask.run(%{"task_id" => "863d42c2", "title" => "t"}, ctx)
    assert_received {:task_updated, @uuid, _}
  end

  test "o 409 nomeado volta ao modelo com o motivo", %{ctx: ctx} do
    Process.put(
      :fake_update_task_error,
      {409, %{"reason" => "tarefa_em_execucao", "message" => "a tarefa está in_progress"}}
    )

    assert {:error, texto} = UpdateTask.run(%{"task_id" => @uuid, "title" => "t"}, ctx)
    assert texto =~ "falha ao corrigir tarefa: tarefa_em_execucao"
    assert texto =~ "in_progress"
  end

  test "Gravado neste turno conta a tarefa corrigida" do
    GravadoNoTurno.anotar("update_task", %{}, {:ok, "ok"})

    payload =
      IdiomaDaResposta.com_idioma_do_autor("pt-BR", fn ->
        TextoDoTurno.payload_do_turno("Corrigi.", "m")
      end)

    assert payload.content =~ "1 tarefa corrigida"
  end
end
