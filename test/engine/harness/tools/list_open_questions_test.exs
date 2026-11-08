defmodule Engine.Harness.Tools.ListOpenQuestionsTest do
  @moduledoc "AT-804 (RN-874): a ferramenta devolve TODAS as perguntas abertas, de qualquer autor."
  use Engine.DataCase, async: false

  alias Engine.Harness.Tools.ListOpenQuestions

  defp projeto! do
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

    {project_id, session_id}
  end

  defp evento!(session_id, seq, type, ator, payload) do
    Engine.Repo.insert_all("session_events", [
      %{
        id: "evt-#{System.unique_integer([:positive])}",
        session_id: Ecto.UUID.dump!(session_id),
        seq: seq,
        type: type,
        actor_kind: "agent",
        actor_id: ator,
        payload: payload,
        created_at: DateTime.add(DateTime.utc_now(), seq, :millisecond)
      }
    ])
  end

  test "lista as abertas de todos os autores; a respondida e a de outro projeto ficam fora" do
    {p, s} = projeto!()
    {_outro, so} = projeto!()

    evento!(s, 1, "artifact.open_question", "criativo", %{
      "questionId" => "q-1",
      "pergunta" => "a?"
    })

    evento!(s, 2, "artifact.open_question", "po", %{"questionId" => "q-2", "pergunta" => "b?"})

    evento!(s, 3, "artifact.open_question", "arquiteto", %{
      "questionId" => "q-3",
      "pergunta" => "c?"
    })

    evento!(s, 4, "artifact.open_question", "po", %{"questionId" => "q-4", "pergunta" => "d?"})
    evento!(s, 5, "open_question.answered", "usuario", %{"questionId" => "q-4"})
    evento!(so, 1, "artifact.open_question", "po", %{"questionId" => "q-x", "pergunta" => "z?"})

    assert {:ok, texto} = ListOpenQuestions.run(%{}, %{project_id: p})
    for q <- ~w(q-1 q-2 q-3), do: assert(texto =~ "questionId=#{q}:")
    for a <- ~w(criativo po arquiteto), do: assert(texto =~ "[autor: #{a}]")
    refute texto =~ "q-4"
    refute texto =~ "q-x"
    assert texto =~ "total: 3"
  end

  test "sem nenhuma, diz que não há" do
    {p, _} = projeto!()
    assert {:ok, "nenhuma pergunta aberta"} = ListOpenQuestions.run(%{}, %{project_id: p})
  end
end
