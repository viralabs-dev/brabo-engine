defmodule Engine.Dev.MemoriaCorrenteTest do
  @moduledoc """
  A corrente da AT-923 (ADR 0293), de ponta a ponta no servidor do dev:
  `report_done` com `como_usar` → cartão escrito no worktree → kickoff da
  PRÓXIMA tarefa já com a mensagem fixada "Memória dos módulos" (RN-1110,
  RN-1112) → correção de gate que leva memória, retrato e o resumo anterior
  (RN-1111).
  """

  use Engine.DataCase, async: false

  alias Engine.Dev.{DevAgentServer, FakeWorktreeManager, MemoriaDoProjeto}
  alias Engine.Gates.FakeGateDispatcher
  alias Engine.Harness.ContextManager
  alias Engine.Sessions.FakeEngineApiClient

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :worktree_manager, FakeWorktreeManager)
    Application.put_env(:engine, :gate_dispatcher, FakeGateDispatcher)
    Application.put_env(:engine, :test_pid, self())

    dir = Path.join(System.tmp_dir!(), "brabo-corrente-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "api/src"))

    File.write!(
      Path.join(dir, "api/package.json"),
      ~s({"name":"api","scripts":{"test":"vitest"}})
    )

    File.write!(Path.join(dir, "api/src/index.ts"), "export function criarAgendamento() {}\n")
    Process.put(:fake_worktree_dir, dir)

    on_exit(fn ->
      File.rm_rf!(dir)
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :worktree_manager)
      Application.delete_env(:engine, :gate_dispatcher)
      Application.delete_env(:engine, :test_pid)
    end)

    project_id = Ecto.UUID.generate()
    container_running!(project_id)

    Process.put(:fake_module_contracts_lidos, %{
      "status" => "declarados",
      "version" => 4,
      "modulos" => [
        %{
          "modulo" => "api",
          "dependeDe" => [],
          "expoe" => [%{"tipo" => "funcao", "assinatura" => "criarAgendamento()"}]
        }
      ],
      "contratosForaDoMapa" => []
    })

    %{dir: dir, project_id: project_id, session_id: Ecto.UUID.generate()}
  end

  defp contexto(titulo) do
    %{
      "task" => %{"id" => "x", "title" => titulo, "description" => ""},
      "story" => %{
        "id" => "st-1",
        "title" => "S",
        "description" => "",
        "rf" => [],
        "rnf" => [],
        "dod" => [],
        "dor" => []
      },
      "businessRules" => [],
      "adrs" => []
    }
  end

  defp roda(project_id, session_id, task_id, titulo, turnos) do
    {:ok, state} =
      DevAgentServer.init({project_id, "dev-api", "api", session_id, nil, nil, 3, nil})

    Process.put(:fake_tasks, [%{"id" => task_id, "title" => titulo}])
    Process.put(:fake_dev_context, contexto(titulo))

    Process.put(:fake_propose_action, %{
      "id" => "pa-1",
      "status" => "executed",
      "executionResult" => %{"exitCode" => 0, "stdout" => "ok"}
    })

    Process.put(:fake_llm_turns, turnos)
    {:noreply, state} = DevAgentServer.handle_cast(:work, state)
    state
  end

  defp terminal,
    do: FakeEngineApiClient.tool_call_response("terminal", %{"command" => "npm test"})

  defp primeiras_mensagens do
    assert_receive {:llm_turn, "dev-api", mensagens, _}, 1_000
    mensagens
  end

  test "report_done → cartão → kickoff da próxima tarefa com a memória fixada → correção",
       %{dir: dir, project_id: project_id, session_id: session_id} do
    # 1ª tarefa: sem cartão ainda; o kickoff avisa e o report_done o escreve.
    estado =
      roda(project_id, session_id, "t1", "Primeira", [
        terminal(),
        FakeEngineApiClient.tool_call_response("report_done", %{
          "summary" => "agendamento criado",
          "como_usar" => "Suba com `npm start` e chame `criarAgendamento()`."
        })
      ])

    sem_memoria =
      Enum.find(
        primeiras_mensagens(),
        &String.starts_with?(&1["content"] || "", "Memória dos módulos (`")
      )

    assert sem_memoria["content"] =~ "Ainda não há memória deste módulo"

    cartao = File.read!(Path.join(dir, ".brabo/memoria/modulos/api.md"))
    assert cartao =~ "`criarAgendamento` (função)"
    assert cartao =~ "- `test`: `vitest`"
    assert cartao =~ "Suba com `npm start`"
    assert cartao =~ "## Contrato declarado (v4)"
    assert File.read!(Path.join(dir, "AGENTS.md")) =~ ".brabo/memoria/"
    assert estado.ultimo_resumo == "agendamento criado"

    # 2ª tarefa do módulo: o kickoff já traz o cartão, fixado.
    flush()

    roda(project_id, session_id, "t2", "Segunda", [
      terminal(),
      FakeEngineApiClient.tool_call_response("report_done", %{"summary" => "ajuste"})
    ])

    memoria =
      Enum.find(
        primeiras_mensagens(),
        &String.starts_with?(&1["content"] || "", "Memória dos módulos (`")
      )

    assert memoria["content"] =~ "Suba com `npm start`"
    assert memoria["content"] =~ "`criarAgendamento` (função)"
    assert memoria["content"] =~ "Contrato declarado (v4)"
    refute memoria["content"] =~ "Ainda não há memória"

    # Fixada: a compactação preserva a mensagem e resume o resto.
    Process.put(:fake_llm_turns, [FakeEngineApiClient.final_response("RESUMO")])
    # O ToolLoop tira a marca `:pinned` antes de chamar o modelo; a fixação é testada na fonte.
    fixada = MemoriaDoProjeto.mensagem(dir, "api", [], 4)
    assert fixada[:pinned] == true
    verboso = String.duplicate("leitura antiga ", 50)

    ctx = %{
      project_id: project_id,
      session_id: session_id,
      agent: "dev-api",
      messages: [
        fixada,
        %{"role" => "assistant", "content" => verboso},
        %{"role" => "tool", "content" => verboso},
        %{"role" => "assistant", "content" => "recente"}
      ],
      context_window: 1,
      compaction_keep_recent: 1
    }

    assert {:ok, out} = ContextManager.maybe_compact(ctx)
    assert fixada in out.messages
    refute Enum.any?(out.messages, &(&1["content"] =~ "leitura antiga"))
  end

  test "a correção de gate leva a memória, o retrato e o resumo do report_done anterior",
       %{project_id: project_id, session_id: session_id} do
    estado =
      roda(project_id, session_id, "t1", "Primeira", [
        terminal(),
        FakeEngineApiClient.tool_call_response("report_done", %{"summary" => "feito na 1ª volta"})
      ])

    flush()
    Process.put(:fake_llm_turns, [FakeEngineApiClient.final_response("não consegui")])

    findings = %{gate: "qa", reason: "faltou o caso X", diagnosis: "detalhe"}
    DevAgentServer.handle_cast({:correct, findings}, estado)

    mensagens = primeiras_mensagens()
    conteudos = Enum.map(mensagens, & &1["content"])

    idx = fn trecho -> Enum.find_index(conteudos, &(is_binary(&1) and &1 =~ trecho)) end

    assert idx.("Implemente a task") < idx.("Memória dos módulos (`")
    assert idx.("Memória dos módulos (`") < idx.("Estado do seu worktree")
    assert idx.("Estado do seu worktree") < idx.("feito na 1ª volta")
    assert idx.("feito na 1ª volta") < idx.("pediu correção nesta PR")
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
