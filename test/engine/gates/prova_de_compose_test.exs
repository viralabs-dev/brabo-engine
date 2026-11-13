defmodule Engine.Gates.ProvaDeComposeTest do
  # AT-922 (RN-1330): os três desfechos da api e o erro nomeado.
  use ExUnit.Case, async: true

  alias Engine.Gates.{ProvaDeCompose, QaLead}
  alias Engine.Sessions.EngineApiClient.Live

  defp consolidar(resultado), do: QaLead.consolidar([{ProvaDeCompose.label(), resultado}])

  test "provou entra no parecer como prova" do
    assert {:ok, %{veredito: "approved", resumo: resumo}} =
             consolidar(ProvaDeCompose.traduzir({:ok, %{"veredito" => "provou"}}))

    assert resumo =~ "compose"
  end

  test "falhou reprova com o motivo e as recusas" do
    r = {:ok, %{"veredito" => "falhou", "motivo" => "build quebrou", "recusas" => ["privileged"]}}

    assert {:ok, %{veredito: "changes_requested", itens: itens}} =
             consolidar(ProvaDeCompose.traduzir(r))

    assert Enum.any?(itens, &(&1 =~ "build quebrou"))
    assert Enum.any?(itens, &(&1 =~ "privileged"))
  end

  test "recusas do broker em mapas viram \"campo: motivo\"" do
    r =
      {:ok,
       %{
         "veredito" => "falhou",
         "motivo" => "compose recusado",
         "resultado" => %{"recusas" => [%{"campo" => "api.build.network", "motivo" => "host"}]}
       }}

    assert {:ok, %{itens: itens}} = ProvaDeCompose.traduzir(r)
    assert "api.build.network: host" in itens
  end

  test "aprova_com_aviso aprova e escreve o aviso com origem infra" do
    r = {:ok, %{"veredito" => "aprova_com_aviso", "aviso" => "sem prova de compose: sem broker"}}

    assert {:ok, %{veredito: "approved", melhorias: [m]}} = consolidar(ProvaDeCompose.traduzir(r))
    assert m =~ "sem prova de compose" and m =~ "origem: infra"
  end

  test "erro ou veredito desconhecido vira bloqueio nomeado com origem" do
    for r <- [{:error, {502, %{}}}, {:ok, %{"veredito" => "x"}}] do
      assert {:blocked, %{origin: "infra", diagnosis: d}} = ProvaDeCompose.traduzir(r)
      assert d =~ "inesperada"
    end
  end

  test "o teto de espera passa dos 645s da api" do
    assert Live.teto_da_prova_de_compose_ms() > 645_000
  end
end
