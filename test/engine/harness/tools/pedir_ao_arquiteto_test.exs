defmodule Engine.Harness.Tools.PedirAoArquitetoTest do
  @moduledoc """
  AT-748 (RN-1012): o pedido do Dev Lead fica como `chat.message` durável do ator
  `dev-lead` e chega ao Arquiteto com o prefixo. O Arquiteto aqui é um GenServer
  de mentira registrado no mesmo nome (`ArquitetoServer.via/1`).
  """

  use ExUnit.Case, async: false

  alias Engine.Agents.ArquitetoServer
  alias Engine.Harness.Tools.PedirAoArquiteto

  defmodule FakeArquiteto do
    use GenServer

    def start_link({sid, test_pid}),
      do: GenServer.start_link(__MODULE__, test_pid, name: ArquitetoServer.via(sid))

    def init(test_pid), do: {:ok, test_pid}

    def handle_call({:user_message, texto, _, _}, _from, test_pid) do
      send(test_pid, {:arquiteto_recebeu, texto})
      {:reply, :ok, test_pid}
    end
  end

  setup do
    Application.put_env(:engine, :engine_api_client, Engine.Sessions.FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())
    on_exit(fn -> Application.delete_env(:engine, :test_pid) end)

    sid = "s-" <> Ecto.UUID.generate()
    start_supervised!({FakeArquiteto, {sid, self()}})
    %{ctx: %{project_id: "p1", session_id: sid, agent: "dev-lead"}}
  end

  test "grava o evento durável do dev-lead e entrega a mensagem ao Arquiteto", %{ctx: ctx} do
    assert {:ok, texto} =
             PedirAoArquiteto.run(%{"pedido" => "scheduling precisa de verifyToken"}, ctx)

    assert texto =~ "entregue"

    assert_received {:event_appended, "p1", _,
                     %{
                       type: "chat.message",
                       actorKind: "agent",
                       actorId: "dev-lead",
                       payload: %{
                         "text" => "[Pedido do Dev Lead] scheduling precisa de verifyToken"
                       }
                     }}

    assert_received {:arquiteto_recebeu, "[Pedido do Dev Lead] scheduling precisa de verifyToken"}
  end

  test "pedido vazio é recusado sem gravar nada", %{ctx: ctx} do
    assert {:error, _} = PedirAoArquiteto.run(%{"pedido" => "  "}, ctx)
    refute_received {:event_appended, _, _, _}
  end

  test "falha ao gravar o evento não chama o Arquiteto", %{ctx: ctx} do
    Process.put(:fake_append_event_error, :boom)
    assert {:error, msg} = PedirAoArquiteto.run(%{"pedido" => "x"}, ctx)
    assert msg =~ "boom"
    refute_received {:arquiteto_recebeu, _}
  end
end
