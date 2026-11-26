defmodule Engine.Dev.RaizDaFundacao do
  @moduledoc """
  RN-1415 a RN-1417 (AT-992). A raiz do workspace (manifesto, lock, README e
  compose) é da tarefa de FUNDAÇÃO e da INTEGRADORA; a tarefa de módulo que a
  altera disputa o arquivo de todos os lotes paralelos (RN-1380). O `report_done`
  dela é recusado com a frase que nomeia o arquivo, e o modelo pede ao Dev Lead.
  """

  alias Engine.Actions.GitCmd

  @raiz ~r/\A(package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|README(\.md)?|(docker-)?compose(\..+)?\.ya?ml)\z/i
  @lock ~r/\A(package-lock\.json|yarn\.lock|pnpm-lock\.yaml)\z/i

  @doc "RN-1416: a fundação (flag da api) ou a integradora (título) é dona da raiz."
  def dona?(task) when is_map(task) do
    # shortcut: a integradora é reconhecida pelo título; vira flag da api se o Dev Lead errar o nome.
    Map.get(task, "fundacao") == true or
      Regex.match?(~r/integra/iu, to_string(Map.get(task, "title", "")))
  end

  def dona?(_), do: false

  @doc "RN-1416: o desbloqueio com orientação do dono libera a raiz para aquela tarefa."
  def autorizada?(%{desbloqueio: %{"orientacao" => o}}) when is_binary(o),
    do: String.trim(o) != ""

  def autorizada?(_), do: false

  @doc """
  Arquivos da raiz (sem `/` no caminho) que o conjunto altera. O lock é derivado
  do `package.json` de um módulo: só conta quando o `package.json` da raiz também mudou.
  """
  def da_raiz(paths) do
    raiz = Enum.filter(paths, &Regex.match?(@raiz, &1))
    if "package.json" in raiz, do: raiz, else: Enum.reject(raiz, &Regex.match?(@lock, &1))
  end

  @doc "Caminhos alterados no worktree (com ou sem commit). Vazio se o git falha."
  def alterados(path) when is_binary(path) do
    with {:error, _} <- GitCmd.run(path, ["rev-parse", "-q", "--verify", "MERGE_HEAD"]),
         {:ok, out} <- GitCmd.run(path, ["status", "--porcelain", "-uall"]) do
      out
      |> String.split("\n", trim: true)
      |> Enum.map(&(&1 |> String.slice(3..-1//1) |> String.split(" -> ") |> List.last()))
    else
      # merge da main em curso (RN-1010): o que vem dela não é do agente.
      _ -> []
    end
  end

  def alterados(_), do: []

  @doc "RN-1415: `nil` se pode concluir; senão a frase devolvida ao modelo."
  def recusa(%{dono_da_raiz: false, workspace_root: root}) do
    case da_raiz(alterados(root)) do
      [] ->
        nil

      arquivos ->
        lista = Enum.join(arquivos, ", ")

        "não é possível concluir: #{lista} é comum a todo o projeto e esta tarefa não pode " <>
          "mudá-lo sozinha. Não tente desfazer: chame `report_blocked` com o motivo " <>
          "\"Preciso mudar #{lista}, que vale para o projeto inteiro. Para seguir, " <>
          "desbloqueie dizendo se pode mudar.\""
    end
  end

  def recusa(_), do: nil
end
