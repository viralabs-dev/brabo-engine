defmodule Engine.Harness.Tools.RetireBusinessRuleTest do
  @moduledoc "RN-1020: o Criativo e o PO retiram a regra obsoleta; a api valida."

  use ExUnit.Case, async: false

  alias Engine.Agents.{CriativoServer, PoServer, Reidratacao}
  alias Engine.Harness.Tools.RetireBusinessRule

  setup do
    Application.put_env(:engine, :engine_api_client, Engine.Sessions.FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())
    on_exit(fn -> Application.delete_env(:engine, :test_pid) end)
    %{ctx: %{project_id: "p1", session_id: "s1", agent: "po"}}
  end

  defp nomes(specs), do: Enum.map(specs, & &1.name)

  test "está no catálogo do Criativo e do PO e de mais ninguém" do
    assert "retire_business_rule" in nomes(CriativoServer.tool_specs())
    assert "retire_business_rule" in nomes(PoServer.tool_specs())

    for mod <- [
          Engine.Agents.ArquitetoServer,
          Engine.Agents.DevLeadServer,
          Engine.Agents.StaffServer,
          Engine.Agents.UxDesignerServer,
          Engine.Infra.InfraLeadServer
        ] do
      refute "retire_business_rule" in nomes(mod.tool_specs())
    end

    refute "retire_business_rule" in nomes(
             Engine.Harness.Tools.specs(Engine.Dev.Tools.registry())
           )
  end

  test "manda à api só o que foi informado, com o papel da sessão", %{ctx: ctx} do
    Process.put(:fake_retire_business_rule, %{
      "ruleId" => "r1",
      "replacedBy" => "r2",
      "storyIds" => ["a", "b"]
    })

    args = %{"rule_id" => "r1", "reason" => "mudou", "replaced_by" => "r2"}
    assert {:ok, texto} = RetireBusinessRule.run(args, ctx)
    assert texto =~ "id=r1"
    assert texto =~ "substituta=r2"
    assert texto =~ "ajustadas=2"

    assert_received {:rule_retired, "r1",
                     %{sessionId: "s1", agentRole: "po", reason: "mudou", replacedBy: "r2"} =
                       corpo}

    refute Map.has_key?(corpo, :questionId)
  end

  test "question_id vai como questionId", %{ctx: ctx} do
    assert {:ok, _} =
             RetireBusinessRule.run(
               %{"rule_id" => "r1", "reason" => "x", "question_id" => "q1"},
               ctx
             )

    assert_received {:rule_retired, "r1", %{questionId: "q1"}}
  end

  test "a recusa da api volta ao agente com o motivo", %{ctx: ctx} do
    Process.put(
      :fake_retire_business_rule_error,
      {400, %{"reason" => "retirada_sem_citacao", "message" => "cite a substituta"}}
    )

    assert {:error, texto} = RetireBusinessRule.run(%{"rule_id" => "r1", "reason" => "x"}, ctx)
    assert texto =~ "retirada_sem_citacao"
    assert texto =~ "cite a substituta"
    assert {:error, _} = RetireBusinessRule.run(%{}, ctx)
  end

  test "sem_regras_retiradas tira só a regra retirada" do
    eventos = [
      %{"id" => "r1", "type" => "artifact.business_rule"},
      %{"id" => "r2", "type" => "artifact.business_rule"},
      %{
        "id" => "e",
        "type" => "artifact.business_rule_retired",
        "payload" => %{"ruleId" => "r1"}
      }
    ]

    assert [%{"id" => "r2"}, %{"id" => "e"}] = Reidratacao.sem_regras_retiradas(eventos)
  end
end
