defmodule Engine.Infra.Tools.ProposeInfraPrTest do
  use ExUnit.Case, async: true

  alias Engine.Infra.Tools.ProposeInfraPr

  test "a spec declara run.app opcional com command e port" do
    run = get_in(ProposeInfraPr.spec(), [:parameters, "properties", "run"])
    app = run["properties"]["app"]

    assert app["properties"]["port"] == %{
             "type" => "integer",
             "minimum" => 1024,
             "maximum" => 65_535
           }

    assert app["required"] == ["command", "port"]
    refute "app" in run["required"]
    assert app["description"] =~ "DENTRO do container de trabalho"
  end

  test "a descrição de run.qa pede user e tmpfs de todo serviço de dados (AT-1015, RN-1521)" do
    d =
      get_in(ProposeInfraPr.spec(), [:parameters, "properties", "run", "properties", "qa"])[
        "description"
      ]

    assert d =~ "999:999"
    assert d =~ "/var/lib/postgresql/data"
    assert d =~ "servico_sem_usuario"
  end
end
