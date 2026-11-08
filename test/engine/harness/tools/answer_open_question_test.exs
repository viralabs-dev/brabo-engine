defmodule Engine.Harness.Tools.AnswerOpenQuestionTest do
  @moduledoc "RN-1003 (AT-741): o agente fecha a pergunta em aberto respondida pelo chat."
  use ExUnit.Case, async: false

  alias Engine.Harness.{ArgumentosDeFerramenta, DecisoesDoProjeto, FluxoDoTime}
  alias Engine.Harness.Tools.AnswerOpenQuestion

  setup do
    Application.put_env(:engine, :engine_api_client, Engine.Sessions.FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :test_pid)
    end)

    %{ctx: %{project_id: "p-1", session_id: "s-1", agent: "criativo"}}
  end

  test "chama a api com sessão, agente e resposta", %{ctx: ctx} do
    assert {:ok, msg} =
             AnswerOpenQuestion.run(%{"questionId" => "q-1", "resposta" => " sim "}, ctx)

    assert msg =~ "fechada"

    assert_received {:open_question_answered, "p-1", "q-1",
                     %{sessionId: "s-1", agentId: "criativo", resposta: "sim"}}
  end

  test "sem resposta o corpo não leva `resposta` (vale a sugestão)", %{ctx: ctx} do
    assert {:ok, _} = AnswerOpenQuestion.run(%{"questionId" => "q-1"}, ctx)
    assert_received {:open_question_answered, "p-1", "q-1", body}
    refute Map.has_key?(body, :resposta)
  end

  test "already_answered é sucesso", %{ctx: ctx} do
    Process.put(:fake_answer_open_question, %{"status" => "already_answered"})
    assert {:ok, msg} = AnswerOpenQuestion.run(%{"questionId" => "q-1"}, ctx)
    assert msg =~ "já estava fechada"
  end

  test "404 vira recusa nomeada e 400 também", %{ctx: ctx} do
    Process.put(:fake_answer_open_question, {:error, {404, %{}}})
    assert {:error, msg} = AnswerOpenQuestion.run(%{"questionId" => "q-9"}, ctx)
    assert msg =~ "q-9 não existe"

    Process.put(:fake_answer_open_question, {:error, {400, %{"message" => "x"}}})
    assert {:error, msg} = AnswerOpenQuestion.run(%{"questionId" => "q-9"}, ctx)
    assert msg =~ "recusou"
  end

  test "sem questionId recusa sem chamar a api", %{ctx: ctx} do
    assert {:error, _} = AnswerOpenQuestion.run(%{}, ctx)
    refute_received {:open_question_answered, _, _, _}
  end

  test "passa por ArgumentosDeFerramenta.executar/4", %{ctx: ctx} do
    assert {:ok, _} =
             ArgumentosDeFerramenta.executar(
               "answer_open_question",
               %{"questionId" => "q-1"},
               [AnswerOpenQuestion.spec()],
               fn a -> AnswerOpenQuestion.run(a, ctx) end
             )
  end

  test "a descrição não nomeia idioma (RN-667)" do
    refute AnswerOpenQuestion.spec().description =~ ~r/pt-BR|português|inglês/i
  end

  test "o fluxo manda fechar só com resposta inequívoca, para os quatro e só eles" do
    for agente <- ~w(criativo po arquiteto dev-lead) do
      t = FluxoDoTime.texto(agente)
      assert t =~ "`answer_open_question`"
      assert t =~ "INEQUÍVOCA"
    end

    refute FluxoDoTime.texto("infra") =~ "answer_open_question"
  end

  test "os quatro perguntadores anunciam a ferramenta" do
    for mod <- [
          Engine.Agents.CriativoServer,
          Engine.Agents.PoServer,
          Engine.Agents.ArquitetoServer,
          Engine.Agents.DevLeadServer
        ] do
      nomes = Enum.map(mod.tool_specs(), & &1.name)
      assert "answer_open_question" in nomes
      assert "list_open_questions" in nomes
    end
  end

  test "o contexto dos quatro leva as perguntas abertas (questionId); outros não" do
    assert DecisoesDoProjeto.anexar([], "nao-e-uuid", "criativo") == []
  end
end
