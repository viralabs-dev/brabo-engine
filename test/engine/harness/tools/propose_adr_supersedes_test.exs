defmodule Engine.Harness.Tools.ProposeAdrSupersedesTest do
  @moduledoc "RN-1069: a ADR nova declara qual ADR substitui."

  use Engine.DataCase, async: false

  alias Engine.Harness.Tools.ProposeAdr
  alias Engine.Repo

  setup do
    Application.put_env(:engine, :engine_api_client, Engine.Sessions.FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :engine_api_client)
      Application.delete_env(:engine, :test_pid)
    end)

    project_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO public.project_repositories
        (id, project_id, provider, external_id, url, default_branch, visibility, provisioned_by)
      VALUES ($1, $2, 'local', '/tmp/repo.git', 'file:///tmp/repo.git', 'main', 'private', $3)
      """,
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        Ecto.UUID.dump!(project_id),
        Ecto.UUID.dump!(Ecto.UUID.generate())
      ]
    )

    %{ctx: %{project_id: project_id, session_id: "s1", agent: "arquiteto"}}
  end

  @args %{"title" => "SQLite", "slug" => "0002-sqlite", "content" => "# ADR"}

  test "supersedes vai ao payload e abre o content com `Substitui:`", %{ctx: ctx} do
    assert {:ok, _} =
             ProposeAdr.run(Map.put(@args, "supersedes", "docs/adr/0001-sqlite.md"), ctx)

    assert_received {:propose_action, "open_adr_pr", _, payload}
    assert payload.supersedes == "0001-sqlite"
    assert payload.content == "Substitui: docs/adr/0001-sqlite.md\n\n# ADR"
  end

  test "sem supersedes o payload e o content ficam como estavam", %{ctx: ctx} do
    assert {:ok, _} = ProposeAdr.run(@args, ctx)
    assert_received {:propose_action, "open_adr_pr", _, payload}
    refute Map.has_key?(payload, :supersedes)
    assert payload.content == "# ADR"
  end

  test "o 400 adr_supersedes_invalido volta ao modelo como texto", %{ctx: ctx} do
    Process.put(
      :fake_propose_action_erro,
      {400, %{"code" => "adr_supersedes_invalido", "message" => "a ADR citada não foi executada"}}
    )

    assert {:error, texto} = ProposeAdr.run(Map.put(@args, "supersedes", "0001-x"), ctx)
    assert texto =~ "não foi executada"
  end

  test "a descrição manda ler as perguntas e as ADRs antes de substituir" do
    d = ProposeAdr.spec().description
    assert d =~ "supersedes" and d =~ "list_open_questions" and d =~ "listar_adrs_propostas"
  end
end
