defmodule Engine.Gates.CloneLimpo do
  @moduledoc """
  AT-921 (RN-1121): o clone limpo do commit sob revisão. O QA rodava a suíte no
  worktree do dev, onde os módulos irmãos já estavam compilados e o
  `node_modules` existia; ninguém provava a instalação a partir do zero.

  O engine prepara `.brabo-qa/clone-limpo/` com `git archive HEAD` (só o que está
  versionado, sem `node_modules`, `dist` nem arquivo solto), SEM Docker e SEM
  LLM extra. Só dispara quando a entrega toca manifesto ou build, ou quando é a
  última tarefa pendente (o entregável): o custo é de 1 a 3 chamadas de
  `terminal` do QA nesses gates, e nas demais tarefas nada muda.
  """

  alias Engine.Actions.GitCmd

  @pasta ".brabo-qa/clone-limpo"

  @manifesto ~r{(^|/)(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Dockerfile[^/]*|docker-compose[^/]*\.ya?ml|tsconfig[^/]*\.json)$}

  @doc "A entrega toca manifesto/build, ou é a última tarefa pendente?"
  @spec disparar?([String.t()], map()) :: boolean()
  def disparar?(arquivos, dev_context) do
    Enum.any?(arquivos, &Regex.match?(@manifesto, &1)) or ultima_tarefa?(dev_context)
  end

  # shortcut: "última pendente" é lida das irmãs e das abertas do módulo (o que o
  # dev-context traz); backlog inteiro, só quando o contexto o expuser.
  @doc "A tarefa é a última pendente do projeto? (também decide a prova de compose, RN-1330)"
  def ultima_tarefa?(dev_context) do
    irmas = Map.get(dev_context, :sibling_tasks, [])
    abertas = Map.get(dev_context, :module_open_tasks, [])
    irmas != [] and Enum.all?(irmas, &(Map.get(&1, "status") == "done")) and abertas == []
  end

  @doc """
  Materializa o clone limpo no worktree. `{:ok, caminho_relativo}` ou
  `{:indisponivel, motivo}` (nunca reprova: o motivo vai ao recorte).
  """
  @spec preparar(Path.t()) :: {:ok, String.t()} | {:indisponivel, String.t()}
  def preparar(worktree) do
    destino = Path.join(worktree, @pasta)
    tar = destino <> ".tar"

    File.rm_rf!(destino)
    File.mkdir_p!(destino)

    with {:ok, _} <- GitCmd.run(worktree, ["archive", "--format=tar", "-o", tar, "HEAD"]),
         {_, 0} <- System.cmd("tar", ["-xf", tar, "-C", destino], stderr_to_stdout: true) do
      File.rm(tar)
      {:ok, @pasta}
    else
      {:error, motivo} -> {:indisponivel, "git archive falhou: #{String.slice(motivo, 0, 200)}"}
      {saida, status} -> {:indisponivel, "tar saiu #{status}: #{String.slice(saida, 0, 200)}"}
    end
  end
end
