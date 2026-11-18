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

  @doc """
  A tarefa é a última do PROJETO? (também decide a prova de compose, RN-1330.)
  A api calcula `ultimaDoProjeto` (AT-982, RN-1350); sem o campo, é falso.
  """
  def ultima_tarefa?(dev_context), do: Map.get(dev_context, :ultima_do_projeto, false)

  @doc """
  Materializa o clone limpo no worktree e, com `raiz`, também em
  `<raiz>/.brabo-qa/clone-limpo` (onde o broker o procura, AT-982). Copia o
  `.env.example` para `.env` quando o clone não tem `.env` (passo 1 do README).
  `{:ok, caminho_relativo}` ou `{:indisponivel, motivo}` (nunca reprova: o
  motivo vai ao recorte).
  """
  @spec preparar(Path.t(), Path.t() | nil) :: {:ok, String.t()} | {:indisponivel, String.t()}
  def preparar(worktree, raiz \\ nil) do
    destinos = [Path.join(worktree, @pasta)] ++ if(raiz, do: [Path.join(raiz, @pasta)], else: [])
    tar = hd(destinos) <> ".tar"

    File.mkdir_p!(Path.dirname(tar))

    with {:ok, _} <- GitCmd.run(worktree, ["archive", "--format=tar", "-o", tar, "HEAD"]),
         :ok <- extrair_em(tar, destinos) do
      File.rm(tar)
      if raiz, do: excluir_do_git(raiz)
      {:ok, @pasta}
    else
      {:error, motivo} -> {:indisponivel, "git archive falhou: #{String.slice(motivo, 0, 200)}"}
      {saida, status} -> {:indisponivel, "tar saiu #{status}: #{String.slice(saida, 0, 200)}"}
    end
  end

  defp extrair_em(tar, destinos) do
    Enum.reduce_while(destinos, :ok, fn destino, :ok ->
      File.rm_rf!(destino)
      File.mkdir_p!(destino)

      case System.cmd("tar", ["-xf", tar, "-C", destino], stderr_to_stdout: true) do
        {_, 0} ->
          copiar_env(destino)
          {:cont, :ok}

        erro ->
          {:halt, erro}
      end
    end)
  end

  defp copiar_env(clone) do
    exemplo = Path.join(clone, ".env.example")
    env = Path.join(clone, ".env")
    if File.regular?(exemplo) and not File.exists?(env), do: File.cp(exemplo, env)
  end

  # O clone da raiz não é versionado: sem isto o projeto o veria como não rastreado.
  defp excluir_do_git(raiz) do
    exclude = Path.join(raiz, ".git/info/exclude")

    if File.dir?(Path.dirname(exclude)) do
      atual = with {:ok, texto} <- File.read(exclude), do: texto, else: (_ -> "")
      unless atual =~ ".brabo-qa/", do: File.write(exclude, atual <> "\n.brabo-qa/\n")
    end
  end
end
