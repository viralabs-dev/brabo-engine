defmodule Engine.Harness.Tools.ConsultarImpactoDoModuloTest do
  @moduledoc "RN-1167 (AT-924): consulta de impacto pelo grafo, contida e sem mentir com o grafo desligado."

  use ExUnit.Case, async: false

  alias Engine.Harness.Tools.ConsultarImpactoDoModulo

  setup do
    Application.put_env(:engine, :engine_api_client, Engine.Sessions.FakeEngineApiClient)
    Application.put_env(:engine, :test_pid, self())

    on_exit(fn ->
      Application.delete_env(:engine, :test_pid)
      Process.delete(:fake_impacto_lido)
    end)

    %{ctx: %{project_id: "p1", session_id: "s1", agent: "dev-x", module: "x"}}
  end

  test "só o nome do módulo, :direct, no registro do dev e fora do global" do
    spec = ConsultarImpactoDoModulo.spec()
    assert Map.keys(spec.parameters["properties"]) == ["modulo"]
    assert ConsultarImpactoDoModulo.category() == :direct
    assert ConsultarImpactoDoModulo in Engine.Dev.Tools.registry()
    refute ConsultarImpactoDoModulo in Engine.Harness.Tools.registry()
  end

  test "caminho feliz: o projeto vem do contexto e o texto traz dependentes e contrato", %{
    ctx: ctx
  } do
    Process.put(:fake_impacto_lido, %{
      "modulo" => "scoring",
      "contratoVersao" => 3,
      "dependentes" => ["game-session"],
      "dependeDe" => [],
      "expoe" => [%{"assinatura" => "score(): n", "tipo" => "funcao"}],
      "decisoes" => [%{"id" => "D1", "titulo" => "Pontuação"}]
    })

    assert {:ok, texto} = ConsultarImpactoDoModulo.run(%{"modulo" => "scoring"}, ctx)
    assert_received {:impacto_consultado, "p1", "scoring"}
    assert texto =~ "game-session"
    assert texto =~ "versão 3"
    assert texto =~ "score(): n"
  end

  test "503 diz grafo desligado, nunca lista vazia", %{ctx: ctx} do
    assert {:error, texto} = ConsultarImpactoDoModulo.run(%{"modulo" => "x"}, ctx)
    assert texto =~ "grafo desligado"
  end

  test "sem modulo é recusa nomeada com as chaves", %{ctx: ctx} do
    assert {:error, texto} = ConsultarImpactoDoModulo.run(%{"outro" => 1}, ctx)
    assert texto =~ "exige `modulo`"
  end
end
