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

  # AT-1023 (RN-1513): a matriz é régua de `approved`.
  describe "approved e a matriz" do
    defp ctx(extra \\ %{}),
      do:
        Map.merge(
          %{messages: [%{"role" => "tool", "name" => "terminal", "content" => "exit 0"}]},
          extra
        )

    defp aprovar(matriz, extra \\ %{}),
      do: EmitQaVerdict.run(%{"veredito" => "approved", "coverageMatrix" => matriz}, ctx(extra))

    test "covered false sem motivo recusa citando a regra; com outra_tarefa aceita" do
      linha = %{"rule" => "só um admin", "tests" => [], "covered" => false}
      assert {:error, msg} = aprovar([linha])
      assert msg =~ "só um admin"
      assert {:ok, _} = aprovar([Map.put(linha, "motivo", "outra_tarefa")])
    end

    test "aceito_pelo_dono exige decisão registrada na tarefa" do
      linha = %{"rule" => "r", "tests" => [], "covered" => false, "motivo" => "aceito_pelo_dono"}
      assert {:error, _} = aprovar([linha], %{decisoes: []})

      assert {:ok, _} =
               aprovar([linha, %{"rule" => "d", "tests" => ["t"], "covered" => true}], %{
                 decisoes: [%{"pergunta" => "p", "resposta" => "s"}]
               })
    end

    test "matriz menor que regras mais decisões recusa" do
      assert {:error, msg} = aprovar([], %{regras: ["a", "b"], decisoes: ["d"]})
      assert msg =~ "faltam 3 regras"
    end

    test "covered true com todos os testes sem prova recusa" do
      linha = %{"rule" => "r", "tests" => ["m/a.test.ts"], "covered" => true}
      assert {:error, _} = aprovar([linha], %{testes_sem_prova: ["m/a.test.ts"]})
      assert {:ok, _} = aprovar([linha], %{testes_sem_prova: ["m/outro.test.ts"]})
    end
  end
end
