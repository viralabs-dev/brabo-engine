defmodule Engine.Harness.FraseParaLeigoTest do
  @moduledoc "RN-1546 (AT-1033): o rótulo de ação e de opção diz o efeito do clique."

  use ExUnit.Case, async: true

  alias Engine.Harness.FraseParaLeigo

  test "recusa os rótulos reais da 31ª, com o motivo" do
    for t <- [
          "Recusar",
          "Pedir gravador ao identidade",
          "Declarar no contrato de identidade",
          "Retomar só as lacunas de teste",
          "Entregar só a casca"
        ],
        do: assert({:error, _} = FraseParaLeigo.rotulo_para_leigo(t), t)

    assert {:error, "tem 1 palavra só" <> _} = FraseParaLeigo.rotulo_para_leigo("Recusar")
    assert {:error, motivo} = FraseParaLeigo.rotulo_para_leigo("Entregar só a casca")
    assert motivo =~ "casca"
  end

  test "aceita rótulos que dizem o efeito" do
    for t <- [
          "Esperar a parte de usuários ficar pronta",
          "Não deixar cancelar",
          "Cancelar com aviso",
          "Tentar de novo",
          "Aumentar o teto e continuar"
        ],
        do: assert(:ok = FraseParaLeigo.rotulo_para_leigo(t), t)
  end

  test "a comparação é por palavra inteira, sem caixa e sem acento" do
    assert {:error, _} = FraseParaLeigo.rotulo_para_leigo("Retomar as LACUNAS agora")
    assert {:error, _} = FraseParaLeigo.rotulo_para_leigo("Evitar a INJECAO agora")
    assert {:error, _} = FraseParaLeigo.rotulo_para_leigo("Rodar a suíte agora")
    assert :ok = FraseParaLeigo.rotulo_para_leigo("Abrir o gatilho agora")
  end

  test "só olha o sentido: a forma continua com frase_para_leigo/2, e não-texto é recusado" do
    assert {:error, _} = FraseParaLeigo.rotulo_para_leigo(nil)
    assert {:error, _} = FraseParaLeigo.frase_para_leigo("Rodar `npm test` agora", 40)
  end
end
