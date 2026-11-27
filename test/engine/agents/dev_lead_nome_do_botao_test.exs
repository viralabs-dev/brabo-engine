defmodule Engine.Agents.DevLeadNomeDoBotaoTest do
  @moduledoc """
  RN-1547 (AT-1033): o texto fixo que vai ao modelo nomeia o botão como a tela
  o mostra ("Tentar de novo"), nunca o nome antigo. Os avisos são privados, então
  a conferência lê o fonte de cada texto.
  """
  use ExUnit.Case, async: true

  @lib Path.expand("../../../lib/engine", __DIR__)

  defp trecho(arquivo, de, ate) do
    src = File.read!(Path.join(@lib, arquivo))
    [_, resto] = String.split(src, de, parts: 2)
    [corpo | _] = String.split(resto, ate, parts: 2)
    corpo
  end

  test "aviso_de_parada nomeia 'Tentar de novo', só convida com mudança e não manda ler o plano" do
    t = trecho("agents/dev_lead_server.ex", "defp aviso_de_parada(info)", "defp aviso_de_decisao")
    assert t =~ "Tentar de novo"
    assert t =~ "algo mudou desde o bloqueio"
    refute t =~ "Desbloquear"
    refute t =~ "`ler_plano`"
    assert t =~ "não comente"
  end

  test "aviso_de_decisao e o plano recusado também dizem 'Tentar de novo'" do
    d = trecho("agents/dev_lead_server.ex", "defp aviso_de_decisao(info)", "defp aviso_de_app(")
    assert d =~ "Tentar de novo"
    refute d =~ "Desbloquear"

    r = trecho("agents/dev_lead_tools.ex", "plano recusado: a execução já está ativa", "}")
    assert r =~ "Tentar de novo"
    refute r =~ "Desbloquear"
  end

  test "nenhum texto de lib/ que vai ao modelo cita 'Desbloquear' como ação do usuário" do
    achados =
      for arq <- Path.wildcard(Path.join(@lib, "**/*.ex")),
          {linha, n} <- arq |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          linha =~ "Desbloquear",
          not String.starts_with?(String.trim(linha), "#"),
          do: "#{Path.relative_to(arq, @lib)}:#{n}"

    assert achados == []
  end
end
