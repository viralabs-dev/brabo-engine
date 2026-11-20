defmodule Engine.Harness.Tools.ListarPrsDeInfra do
  @moduledoc """
  Ferramenta de LEITURA da Infra (AT-986, achado 8): o estado ATUAL das PRs que
  ela propôs (`open_infra_pr`). No TP-01 29 a Infra não soube que a PR #1 tinha
  sido mergeada e respondeu de memória. Mesma consulta e mesmo cruzamento com o
  `git_merge` de `ListarAdrsPropostas` (RN-845); sem parâmetro, escopo no projeto.
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Harness.Tools.ListarAdrsPropostas

  @rotulo %{
    vazio: "Nenhuma PR de infra proposta neste projeto (nenhuma ação `open_infra_pr`).",
    cabecalho: "PR(s) de infra proposta(s)",
    antiga: "PR(s) de infra mais antiga(s)"
  }

  @impl true
  def spec do
    %{
      name: "listar_prs_de_infra",
      description:
        "Lista as PRs de infraestrutura que você propôs neste projeto (`propose_infra_pr`) " <>
          "com o estado ATUAL de cada uma: pendente, aprovada, recusada, executada (com a " <>
          "URL e se a PR está aberta ou já mergeada) ou falhada. Não recebe parâmetro. " <>
          "Antes de afirmar o estado de uma PR sua, consulte esta ferramenta.",
      parameters: %{"type" => "object", "properties" => %{}, "required" => []}
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(_args, ctx) do
    {:ok, ListarAdrsPropostas.consultar(ctx.project_id, "open_infra_pr", @rotulo)}
  rescue
    e -> {:error, "falha ao ler as PRs de infra: #{Exception.message(e)}"}
  end
end
