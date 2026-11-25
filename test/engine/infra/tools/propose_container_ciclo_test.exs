defmodule Engine.Infra.Tools.ProposeContainerCicloTest do
  # AT-980 (RN-1363): o contrato das três specs; o comportamento está no InfraLeadServerTest.
  use ExUnit.Case, async: true

  alias Engine.Infra.Tools.{
    ProposeContainerStop,
    ProposeContainerRemove,
    ProposeContainerRecreate
  }

  for {mod, nome} <- [
        {ProposeContainerStop, "propose_container_stop"},
        {ProposeContainerRemove, "propose_container_remove"},
        {ProposeContainerRecreate, "propose_container_recreate"}
      ] do
    test "#{nome}: spec, categoria e salvaguarda de run/2" do
      assert unquote(mod).spec().name == unquote(nome)
      assert unquote(mod).spec().parameters["required"] == []
      assert unquote(mod).category() == :direct
      assert {:error, msg} = unquote(mod).run(%{}, %{})
      assert msg =~ "InfraLeadServer"
    end
  end

  test "só o recreate aceita ports" do
    assert Map.has_key?(ProposeContainerRecreate.spec().parameters["properties"], "ports")
    refute Map.has_key?(ProposeContainerStop.spec().parameters["properties"], "ports")
  end
end
