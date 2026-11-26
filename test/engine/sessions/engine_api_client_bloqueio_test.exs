defmodule Engine.Sessions.EngineApiClientBloqueioTest do
  @moduledoc """
  AT-1021 (RN-1529): o corpo do `/block` leva a `explicacao` com os nomes de campo
  do contrato com a api (`codigo`, `causa`, `acoes[].id|rotulo|orientacao`).
  """
  use ExUnit.Case, async: false

  alias Engine.Dev.ExplicacaoDoBloqueio
  alias Engine.Sessions.EngineApiClient.Live

  defmodule Api do
    @moduledoc false
    @behaviour Plug
    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, opts) do
      {:ok, corpo, conn} = Plug.Conn.read_body(conn)
      send(Keyword.fetch!(opts, :pid), {:corpo, conn.request_path, Jason.decode!(corpo)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{id: "t1", blocked: true}))
    end
  end

  setup do
    anterior = Application.get_env(:engine, :api_url)

    on_exit(fn ->
      if anterior,
        do: Application.put_env(:engine, :api_url, anterior),
        else: Application.delete_env(:engine, :api_url)
    end)

    {:ok, pid} =
      Bandit.start_link(plug: {Api, pid: self()}, port: 0, ip: :loopback, startup_log: false)

    {:ok, {_ip, porta}} = ThousandIsland.listener_info(pid)
    Application.put_env(:engine, :api_url, "http://127.0.0.1:#{porta}")
    :ok
  end

  test "o /block manda a explicacao do catalogo" do
    assert {:ok, _} =
             Live.mark_task_blocked(
               "p",
               "s",
               "t",
               "r",
               "d",
               "dev-api",
               "infra",
               ExplicacaoDoBloqueio.de(:qa_instancia_indisponivel)
             )

    assert_receive {:corpo, "/internal/sessions/s/tasks/t/block", corpo}
    assert corpo["origin"] == "infra"

    assert %{
             "codigo" => "qa_instancia_indisponivel",
             "causa" => "A QA de Automação não conseguiu subir o ambiente de teste.",
             "acoes" => [
               %{"id" => "tentar_de_novo", "rotulo" => "Tentar de novo", "orientacao" => ""}
             ]
           } = corpo["explicacao"]
  end

  test "a explicacao do agente vai sem codigo e sem id" do
    {:ok, e} =
      ExplicacaoDoBloqueio.do_agente("Falta o app.", [
        %{"rotulo" => "Concluir sem subir o app", "orientacao" => "Conclua sem a prova."}
      ])

    assert {:ok, _} = Live.mark_task_blocked("p", "s", "t", "r", "d", "dev-api", "modelo", e)
    assert_receive {:corpo, _, %{"explicacao" => expl}}

    assert expl == %{
             "causa" => "Falta o app.",
             "acoes" => [
               %{"rotulo" => "Concluir sem subir o app", "orientacao" => "Conclua sem a prova."}
             ]
           }
  end

  test "o veredito needs_user_decision manda opcoes e detalhe como campos de topo" do
    opcoes = [%{"rotulo" => "Testar com banco", "resposta" => "Suba o banco."}]
    extras = %{pergunta: "Quer testar com banco?", opcoes: opcoes, detalhe: "relato técnico"}

    assert {:ok, _} =
             Live.record_gate_verdict(
               "p",
               "s",
               "t",
               "qa",
               "needs_user_decision",
               "r",
               [],
               3,
               extras
             )

    assert_receive {:corpo, "/internal/sessions/s/gates/verdict", corpo}
    assert corpo["opcoes"] == opcoes
    assert corpo["detalhe"] == "relato técnico"
    assert corpo["pergunta"] == "Quer testar com banco?"
    refute Map.has_key?(corpo, "extras")
  end
end
