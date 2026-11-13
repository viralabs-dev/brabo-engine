defmodule Engine.Gates.ProvaDeCompose do
  @moduledoc """
  AT-922 (RN-1330): o QA da ÚLTIMA tarefa do projeto pede à api a prova do
  `docker compose up --build` real (a api manda ao broker, que valida o compose
  por allowlist, sobe, sonda `/docs` e `/openapi.json` e limpa sempre). O engine
  não toca Docker: traduz o veredito da api no resultado que o `QaLead` consolida.

  - `provou`: aprova; o resumo registra a prova.
  - `falhou`: reprova com o motivo e as `recusas` (origem `codigo`, é o projeto).
  - `aprova_com_aviso`: aprova e o aviso vai no parecer (`melhorias`, origem
    `infra`), nunca calado ("sem prova de compose").
  - erro, status fora do contrato ou veredito desconhecido: bloqueio nomeado
    com origem `infra` (RN-059); a task não é reprovada por falha que não é dela.
  """

  alias Engine.Sessions.EngineApiClient

  @label "Prova de compose"

  def label, do: @label

  @spec provar(String.t(), String.t()) :: {:ok, map()} | {:blocked, map()}
  def provar(project_id, task_id) do
    project_id |> EngineApiClient.provar_compose_de_qa(task_id) |> traduzir()
  end

  @doc false
  def traduzir({:ok, %{"veredito" => "provou"}}),
    do:
      {:ok,
       %{
         veredito: "approved",
         resumo: "compose real provado (up --build, /docs e /openapi.json)",
         itens: []
       }}

  def traduzir({:ok, %{"veredito" => "falhou"} = r}) do
    itens = [
      texto(r["motivo"], "o compose real não subiu") | Enum.map(recusas(r), &texto(&1, ""))
    ]

    {:ok,
     %{
       veredito: "changes_requested",
       resumo: "o compose real do projeto não subiu (origem: codigo)",
       itens: Enum.reject(itens, &(&1 == ""))
     }}
  end

  def traduzir({:ok, %{"veredito" => "aprova_com_aviso"} = r}) do
    aviso = texto(r["aviso"] || r["motivo"], "sem prova de compose")

    {:ok,
     %{
       veredito: "approved",
       resumo: "sem prova de compose",
       itens: [],
       melhorias: ["#{aviso} (origem: infra)"]
     }}
  end

  def traduzir(outro) do
    {:blocked,
     %{
       reason: "a prova do compose não devolveu um veredito reconhecido",
       diagnosis: "resposta inesperada: #{inspect(outro, limit: 5, printable_limit: 200)}",
       origin: "infra"
     }}
  end

  defp recusas(r) do
    case r["recusas"] || get_in(r, ["resultado", "recusas"]) do
      lista when is_list(lista) -> lista
      _ -> []
    end
  end

  # O broker manda `[{campo, motivo}]`; texto solto também vale.
  defp texto(%{"campo" => campo, "motivo" => motivo}, _), do: "#{campo}: #{motivo}"
  defp texto(nil, padrao), do: padrao
  defp texto(t, _) when is_binary(t), do: t
  defp texto(t, _), do: inspect(t, limit: 5, printable_limit: 200)
end
