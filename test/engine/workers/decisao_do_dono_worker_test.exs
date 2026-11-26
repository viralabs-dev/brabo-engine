defmodule Engine.Workers.DecisaoDoDonoWorkerTest do
  use ExUnit.Case, async: false

  alias Engine.Workers.DecisaoDoDonoWorker

  defp job(autor) do
    %Oban.Job{
      args: %{
        "event_type" => "open_question.answered",
        "payload" => %{
          "projectId" => "p-dec",
          "autor" => autor,
          "pergunta" => "Recriar o Dockerfile?",
          "resposta" => "Sim, no módulo entrega"
        }
      }
    }
  end

  test "RN-1516: pergunta do dev-lead acorda o Dev Lead com a decisão" do
    Engine.Dev.Wake.subscribe("p-dec", "dev-lead")
    assert :ok = DecisaoDoDonoWorker.perform(job("dev-lead"))

    assert_receive {:decisao_do_dono,
                    %{pergunta: "Recriar o Dockerfile?", resposta: "Sim, no módulo entrega"}}
  end

  test "RN-1516: outro autor não entrega nada" do
    Engine.Dev.Wake.subscribe("p-dec", "dev-lead")
    assert :ok = DecisaoDoDonoWorker.perform(job("po"))
    refute_receive {:decisao_do_dono, _}, 50
  end
end
