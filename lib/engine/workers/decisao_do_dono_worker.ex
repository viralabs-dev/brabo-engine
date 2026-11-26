defmodule Engine.Workers.DecisaoDoDonoWorker do
  @moduledoc """
  RN-1516 (AT-1019): a api gravou `open_question.answered` na mesma transação
  da resposta do dono. Quando quem perguntou foi o Dev Lead, ele é acordado com
  `{:decisao_do_dono, payload}` para executar a decisão ou dizer em uma frase o
  que só o dono faz. Outro autor (Criativo, PO, Arquiteto) segue como antes.
  Entrega AT-MOST-ONCE, como o `Wake`: a decisão continua no contexto passivo
  (`DecisoesDoProjeto`).
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  @impl true
  def perform(%Oban.Job{
        args: %{
          "event_type" => "open_question.answered",
          "payload" => %{"autor" => "dev-lead", "projectId" => project_id} = p
        }
      })
      when is_binary(project_id) do
    Engine.Dev.Wake.deliver(
      project_id,
      "dev-lead",
      {:decisao_do_dono,
       %{pergunta: to_string(p["pergunta"]), resposta: to_string(p["resposta"])}}
    )

    :ok
  end

  def perform(%Oban.Job{}), do: :ok
end
