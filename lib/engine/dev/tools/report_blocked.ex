defmodule Engine.Dev.Tools.ReportBlocked do
  @moduledoc """
  Sinaliza que o DevAgent NÃO consegue concluir a task e por quê — o modelo
  usa quando decide (após tentar) que está travado. Sempre aceito (não há o
  que enforçar num bloqueio); o hook `Engine.Dev.Hooks.Termination` termina o
  loop e o `DevAgentServer` devolve a task com o diagnóstico.

  AT-1021 (RN-1529): o bloqueio leva também a explicação para quem não programa
  (`causa_para_leigo` e 1..2 `acoes`), validada pela regra de linguagem de
  `Engine.Dev.ExplicacaoDoBloqueio`; fora da regra, a recusa volta ao modelo,
  que reescreve. (`causa` já é o enum de quem tem a culpa; por isso o nome novo.)
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Dev.ExplicacaoDoBloqueio

  @impl true
  def spec do
    %{
      name: "report_blocked",
      description:
        "Sinaliza que não é possível concluir a task e registra o diagnóstico. " <>
          "Não serve para \"falta ferramenta de git\": commit, push e PR são feitos " <>
          "por `report_done`.",
      parameters: %{
        "type" => "object",
        "properties" => %{
          "reason" => %{"type" => "string", "description" => "motivo curto do bloqueio"},
          "diagnosis" => %{
            "type" => "string",
            "description" => "diagnóstico detalhado — o que foi tentado, o que falhou"
          },
          "causa" => %{
            "type" => "string",
            "enum" => ["nao_consegui", "depende_de_outra_tarefa", "precisa_de_decisao"],
            "description" =>
              "padrão `nao_consegui`; use `depende_de_outra_tarefa` ou `precisa_de_decisao` " <>
                "quando o bloqueio não é falha sua"
          },
          "causa_para_leigo" => %{
            "type" => "string",
            "description" =>
              "a causa do bloqueio em UMA frase de até 160 caracteres, para quem não programa: " <>
                "sem nome de arquivo, caminho, identificador, código de erro, número de erro " <>
                "nem crase (esses ficam em `diagnosis`)"
          },
          "acoes" => %{
            "type" => "array",
            "description" =>
              "1 ou 2 ações prontas que o usuário aprova com um clique; a `orientacao` de " <>
                "cada uma é o que você receberá ao retomar (texto livre, pode ser técnica)",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "rotulo" => %{
                  "type" => "string",
                  "description" => "texto do botão, até 40 caracteres, sem jargão"
                },
                "orientacao" => %{"type" => "string"}
              },
              "required" => ["rotulo", "orientacao"]
            }
          },
          "precisa_de" => %{
            "type" => "string",
            "enum" => ["arquiteto"],
            "description" =>
              "use `arquiteto` quando falta uma interface (função, rota, evento, tabela, " <>
                "identidade) de OUTRO módulo no contrato: o pedido segue ao Arquiteto sem " <>
                "passar pelo Dev Lead"
          }
        },
        "required" => ["reason", "diagnosis", "causa_para_leigo", "acoes"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(%{"reason" => reason} = args, _ctx) when is_binary(reason) do
    case ExplicacaoDoBloqueio.do_agente(args["causa_para_leigo"], args["acoes"]) do
      {:ok, _} -> {:ok, "bloqueio registrado: #{reason}"}
      {:error, msg} -> {:error, "report_blocked recusado: " <> msg}
    end
  end

  def run(_args, _ctx),
    do: {:error, "report_blocked exige `reason`, `diagnosis`, `causa_para_leigo` e `acoes`"}
end
