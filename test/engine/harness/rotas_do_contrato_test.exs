defmodule Engine.Harness.RotasDoContratoTest do
  use ExUnit.Case, async: true

  alias Engine.Harness.RotasDoContrato

  # Contrato v3 do TP-01 26ª: as rotas são do `api`.
  @contratos [
    %{
      "modulo" => "api",
      "expoe" => [
        %{"assinatura" => "POST /horarios"},
        %{"assinatura" => "GET /horarios/disponiveis"}
      ]
    },
    %{"modulo" => "scheduling", "expoe" => [%{"assinatura" => "listarHorarios(): Horario[]"}]}
  ]
  @tarefas [
    %{
      "id" => "t1",
      "title" => "Implementar POST /horarios e GET /horarios/disponiveis",
      "description" => ""
    },
    %{"id" => "t2", "title" => "Implementar GET /nada", "description" => nil}
  ]

  test "rota do contrato atribuída a outro módulo diverge e nomeia o dono" do
    linhas =
      RotasDoContrato.donos_divergentes(@contratos, @tarefas, [
        %{"taskId" => "t1", "modulo" => "scheduling"}
      ])

    assert [l1, l2] = linhas
    assert l1 =~ "POST /horarios" and l1 =~ "`api`"
    assert l2 =~ "GET /horarios/disponiveis"
  end

  test "mesma tarefa no módulo dono não diverge" do
    assert [] =
             RotasDoContrato.donos_divergentes(@contratos, @tarefas, [
               %{"taskId" => "t1", "modulo" => "api"}
             ])
  end

  test "rota fora do contrato é ignorada" do
    assert [] =
             RotasDoContrato.donos_divergentes(@contratos, @tarefas, [
               %{"taskId" => "t2", "modulo" => "scheduling"}
             ])
  end
end
