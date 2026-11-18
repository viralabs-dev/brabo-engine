defmodule Engine.Harness.Tools.PedirAInfraTest do
  @moduledoc "AT-996 (RN-1335): `pedir_a_infra` entrega à Infra e a resposta volta ao Dev Lead."

  use ExUnit.Case, async: false

  alias Engine.Harness.Tools.PedirAInfra
  alias Engine.Infra.InfraLeadServer

  defmodule FakeInfra do
    use GenServer

    def start_link({sid, test_pid}),
      do: GenServer.start_link(__MODULE__, test_pid, name: InfraLeadServer.via(sid))

    def init(test_pid), do: {:ok, test_pid}

    def handle_call({:user_message, texto, _, _}, _from, test_pid) do
      send(test_pid, {:infra_recebeu, texto})
      {:reply, :ok, test_pid}
    end
  end

  setup do
    Application.put_env(:engine, :engine_api_client, Engine.Sessions.FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())
    on_exit(fn -> Application.delete_env(:engine, :test_pid) end)

    sid = "s-" <> Ecto.UUID.generate()
    start_supervised!({FakeInfra, {sid, self()}})
    %{ctx: %{project_id: "p1", session_id: sid, agent: "dev-lead"}}
  end

  test "grava o chat.message do dev-lead e entrega o pedido à Infra", %{ctx: ctx} do
    assert {:ok, texto} = PedirAInfra.run(%{"mensagem" => "o app não sobe"}, ctx)
    assert texto =~ "entregue"

    assert_received {:event_appended, "p1", _,
                     %{
                       actorId: "dev-lead",
                       payload: %{"text" => "[Pedido do Dev Lead] o app não sobe"}
                     }}

    assert_received {:infra_recebeu, "[Pedido do Dev Lead] o app não sobe"}
  end

  test "mensagem vazia é recusada", %{ctx: ctx} do
    assert {:error, _} = PedirAInfra.run(%{"mensagem" => " "}, ctx)
    refute_received {:infra_recebeu, _}
  end

  test "a última fala da Infra volta ao Dev Lead como {:resposta_da_infra, _}" do
    Engine.Dev.Wake.subscribe("p9", "dev-lead")

    InfraLeadServer.responder_ao_dev_lead(%{
      project_id: "p9",
      messages: [
        %{"role" => "assistant", "content" => "reiniciei o container"},
        %{"role" => "tool", "content" => "x"}
      ]
    })

    assert_received {:resposta_da_infra, "reiniciei o container"}
  end
end
