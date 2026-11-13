defmodule Engine.Gates.Tools.EmitQaVerdictTest do
  # AT-905 (RN-1116, RN-1117)
  use ExUnit.Case, async: true

  alias Engine.Gates.Tools.EmitQaVerdict

  test "recusa changes_requested sem item bloqueante" do
    args = %{"veredito" => "changes_requested", "itens" => [], "melhorias" => ["x"]}
    assert {:error, msg} = EmitQaVerdict.run(args, %{})
    assert msg =~ "melhorias"
  end

  test "aceita changes_requested com item, texto ou objeto" do
    assert {:ok, _} =
             EmitQaVerdict.run(%{"veredito" => "changes_requested", "itens" => ["a"]}, %{})

    json = ~s([{"texto":"a","origem":"anterior"}])

    assert {:ok, _} =
             EmitQaVerdict.run(%{"veredito" => "changes_requested", "itens" => json}, %{})
  end

  test "a spec declara melhorias" do
    assert Map.has_key?(EmitQaVerdict.spec().parameters["properties"], "melhorias")
  end
end
