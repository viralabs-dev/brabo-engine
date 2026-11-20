defmodule Engine.Harness.Tools.ListarPrsDeInfraTest do
  @moduledoc """
  AT-986 (achado 8): a Infra não sabia que a PR #1 tinha sido mergeada. A leitura
  reusa a consulta das ADRs (RN-845) com `open_infra_pr`.
  """

  use Engine.DataCase, async: false

  alias Engine.Harness.Tools.ListarPrsDeInfra

  defp acao!(project_id, tipo, status, payload, extra \\ %{}) do
    Repo.insert_all("proposed_actions", [
      Map.merge(
        %{
          id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          project_id: Ecto.UUID.dump!(project_id),
          session_id: Ecto.UUID.dump!(Ecto.UUID.generate()),
          action_type: tipo,
          status: status,
          resolved_policy: "require_approval",
          actor_kind: "agent",
          actor_id: "infra",
          payload: payload
        },
        extra
      )
    ])
  end

  test "PR de infra mergeada aparece como mergeada; ADR não entra" do
    p = Ecto.UUID.generate()

    acao!(p, "open_infra_pr", "executed", %{"title" => "Compose"}, %{
      execution_result: %{"pullRequestUrl" => "local://x/pull/1", "pullRequestId" => "1"}
    })

    acao!(p, "git_merge", "executed", %{"pullRequestId" => "1"}, %{
      decided_at: ~U[2026-11-14 02:00:00.000000Z]
    })

    acao!(p, "open_adr_pr", "pending", %{"title" => "ADR banco"})

    assert {:ok, texto} = ListarPrsDeInfra.run(%{}, %{project_id: p})
    assert texto =~ "1 PR(s) de infra proposta(s)"
    assert texto =~ "Compose | APROVADA e EXECUTADA | PR MERGEADA em 2026-11-14T02:00:00Z"
    refute texto =~ "ADR banco"
  end

  test "sem PR de infra diz que não há" do
    assert {:ok, texto} = ListarPrsDeInfra.run(%{}, %{project_id: Ecto.UUID.generate()})
    assert texto =~ "Nenhuma PR de infra proposta"
  end

  test "o catálogo da Infra inclui a ferramenta" do
    assert "listar_prs_de_infra" in Enum.map(Engine.Infra.InfraLeadServer.tool_specs(), & &1.name)
  end
end
