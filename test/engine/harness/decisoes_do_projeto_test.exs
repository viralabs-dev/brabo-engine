defmodule Engine.Harness.DecisoesDoProjetoTest do
  @moduledoc "RN-874 (AT-526): o turno do PO leva as decisões e as perguntas abertas do projeto."
  use Engine.DataCase, async: false

  alias Engine.Harness.DecisoesDoProjeto

  setup do
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

    %{project_id: project_id, session_id: session_id}
  end

  defp evento!(session_id, seq, type, payload) do
    Engine.Repo.insert_all("session_events", [
      %{
        id: "evt-#{System.unique_integer([:positive])}",
        session_id: Ecto.UUID.dump!(session_id),
        seq: seq,
        type: type,
        actor_kind: "agent",
        actor_id: "criativo",
        payload: payload,
        created_at: DateTime.add(DateTime.utc_now(), seq, :millisecond)
      }
    ])
  end

  @msgs [%{"role" => "user", "content" => "oi"}]

  test "o turno do PO leva a decisão e só a pergunta AINDA aberta", %{
    project_id: p,
    session_id: s
  } do
    evento!(s, 1, "artifact.open_question", %{"questionId" => "q-1", "pergunta" => "404?"})
    evento!(s, 2, "open_question.answered", %{"questionId" => "q-1", "resposta" => "sim"})
    evento!(s, 3, "artifact.decision_record", %{"choice" => "responde 404", "context" => "q-1"})
    evento!(s, 4, "artifact.open_question", %{"questionId" => "q-2", "pergunta" => "expira?"})

    [_, %{"role" => "system", "content" => texto}] = DecisoesDoProjeto.anexar(@msgs, p, "po")

    assert texto =~ "responde 404"
    assert texto =~ "questionId=q-2: expira?"
    refute texto =~ "q-1: 404?"
    assert texto =~ "nunca escreva \"pergunta em aberto N\""
  end

  test "a decisão sai com o questionId e as histórias de afeta", %{project_id: p, session_id: s} do
    evento!(s, 1, "artifact.decision_record", %{
      "choice" => "responde 404",
      "context" => "404?",
      "questionId" => "q-1",
      "afeta" => %{"historias" => ["h-1", "h-2"]}
    })

    [_, %{"content" => texto}] = DecisoesDoProjeto.anexar(@msgs, p, "po")
    assert texto =~ "[questionId=q-1; histórias: h-1, h-2]"
  end

  test "custo de entrada tem teto", %{project_id: p, session_id: s} do
    for i <- 1..30 do
      evento!(s, i, "artifact.decision_record", %{
        "choice" => String.duplicate("x", 1000),
        "context" => "c"
      })
    end

    [_, %{"content" => texto}] = DecisoesDoProjeto.anexar(@msgs, p, "po")
    assert String.length(texto) <= DecisoesDoProjeto.teto_de_caracteres()
  end

  test "sem decisões nem perguntas não acrescenta nada", %{project_id: p} do
    assert DecisoesDoProjeto.anexar(@msgs, p, "po") == @msgs
  end

  test "os quatro perguntadores recebem o questionId e a sugestão; outro agente não", %{
    project_id: p,
    session_id: s
  } do
    evento!(s, 1, "artifact.open_question", %{
      "questionId" => "q-7",
      "pergunta" => "expira?",
      "sugestao" => "30 dias"
    })

    for agente <- ~w(criativo po arquiteto dev-lead) do
      [_, %{"content" => texto}] = DecisoesDoProjeto.anexar(@msgs, p, agente)
      assert texto =~ "questionId=q-7"
      assert texto =~ "sugestão: 30 dias"
    end

    assert DecisoesDoProjeto.anexar(@msgs, p, "infra") == @msgs
  end

  test "as 7 do TP-01 27ª: as abertas vêm antes das decisões e nenhum id é cortado", %{
    project_id: p,
    session_id: s
  } do
    longo = String.duplicate("x", 200)

    for n <- 1..6,
        do:
          evento!(s, n, "artifact.decision_record", %{
            "choice" => longo,
            "context" => longo,
            "questionId" => "dec-#{n}"
          })

    ids = for n <- 1..7, do: "abcd000#{n}-1111-2222-3333-444455556666"

    for {id, n} <- Enum.with_index(ids, 10),
        do:
          evento!(s, n, "artifact.open_question", %{
            "questionId" => id,
            "pergunta" => String.duplicate("x", 150),
            "sugestao" => String.duplicate("y", 60)
          })

    texto = DecisoesDoProjeto.texto(p)
    for id <- ids, do: assert(texto =~ "questionId=#{id}:")
    assert String.length(texto) <= DecisoesDoProjeto.teto_de_caracteres()
    {abertas, _} = :binary.match(texto, "Perguntas AINDA abertas")
    {decisoes, _} = :binary.match(texto, "Decisões do usuário")
    assert abertas < decisoes
  end

  test "com mais abertas do que cabe, o texto diz o total e cita list_open_questions", %{
    project_id: p,
    session_id: s
  } do
    for n <- 1..12 do
      evento!(s, n, "artifact.open_question", %{
        "questionId" => "abcd#{String.pad_leading("#{n}", 4, "0")}-1111-2222-3333-444455556666",
        "pergunta" => String.duplicate("p", 240),
        "sugestao" => String.duplicate("s", 240)
      })
    end

    texto = DecisoesDoProjeto.texto(p)
    assert texto =~ "Há 12 perguntas abertas no total"
    assert texto =~ "list_open_questions"
    assert String.length(texto) <= DecisoesDoProjeto.teto_de_caracteres()
    # o corte é por linha inteira: toda linha com questionId traz o id completo (36 caracteres)
    for [id] <- Regex.scan(~r/questionId=(\S*?):/, texto, capture: :all_but_first),
        do: assert(String.length(id) == 36)
  end

  test "leitura que falha deixa o turno sem a mensagem, sem queda" do
    assert DecisoesDoProjeto.anexar(@msgs, "nao-e-uuid", "po") == @msgs
  end
end
