defmodule Engine.Harness.Tools.DeclareOpenQuestionTest do
  @moduledoc "RN-1505 (AT-1018): pergunta de texto igual a uma aberta ou respondida é recusada."
  use Engine.DataCase, async: false

  alias Engine.Harness.Tools.DeclareOpenQuestion
  alias Engine.Sessions.FakeEngineApiClient

  setup do
    Application.put_env(:engine, :engine_api_client, FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :test_pid)
    end)

    project_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    agora = DateTime.utc_now() |> DateTime.truncate(:second)

    Engine.Repo.insert_all("projects", [
      %{
        id: Ecto.UUID.dump!(project_id),
        name: "cobaia",
        slug: "cobaia-#{System.unique_integer([:positive])}",
        created_at: agora,
        updated_at: agora
      }
    ])

    Engine.Repo.insert_all("sessions", [
      %{
        id: Ecto.UUID.dump!(session_id),
        project_id: Ecto.UUID.dump!(project_id),
        created_at: agora
      }
    ])

    %{ctx: %{project_id: project_id, session_id: session_id, agent: "dev-lead"}}
  end

  defp evento!(ctx, seq, type, payload) do
    Engine.Repo.insert_all("session_events", [
      %{
        id: "evt-#{System.unique_integer([:positive])}",
        session_id: Ecto.UUID.dump!(ctx.session_id),
        seq: seq,
        type: type,
        actor_kind: "agent",
        actor_id: "dev-lead",
        payload: payload,
        created_at: DateTime.add(DateTime.utc_now(), seq, :millisecond)
      }
    ])
  end

  defp args(pergunta), do: %{"pergunta" => pergunta, "afeta" => %{}}

  test "igual (caixa e acento) a uma ABERTA: erro com o questionId, sem gravar", %{ctx: ctx} do
    evento!(ctx, 1, "artifact.open_question", %{
      "questionId" => "q-1",
      "pergunta" => "Aprovação do plano?"
    })

    assert {:error, msg} = DeclareOpenQuestion.run(args("aprovacao  do PLANO?"), ctx)
    assert msg =~ "já está aberta (questionId=q-1)"
    refute_received {:append_event, _, _, _}
  end

  test "igual a uma RESPONDIDA: erro com a escolha, sem gravar", %{ctx: ctx} do
    evento!(ctx, 1, "artifact.open_question", %{
      "questionId" => "q-1",
      "pergunta" => "Merge automático?"
    })

    evento!(ctx, 2, "open_question.answered", %{"questionId" => "q-1", "resposta" => "ligado"})

    assert {:error, msg} = DeclareOpenQuestion.run(args("merge automatico?"), ctx)
    assert msg =~ "já respondeu: ligado"
    refute_received {:append_event, _, _, _}
  end

  test "pergunta diferente grava", %{ctx: ctx} do
    evento!(ctx, 1, "artifact.open_question", %{"questionId" => "q-1", "pergunta" => "uma?"})
    assert {:ok, msg} = DeclareOpenQuestion.run(args("outra?"), ctx)
    assert msg =~ "pergunta em aberto registrada"
  end
end
