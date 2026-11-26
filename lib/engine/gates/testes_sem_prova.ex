defmodule Engine.Gates.TestesSemProva do
  @moduledoc """
  AT-1023 (RN-1513): acha os arquivos de teste que RETORNAM CEDO, sem asserir
  nada, quando falta uma variável de ambiente (`if (!bancoDeTeste) return;`).
  O teste sai verde sem provar nada e o JUnit o conta como `passou`; aqui ele
  vira "não coberto". `it.skip` NÃO entra: o JUnit já o conta como pulado.

  shortcut: regex só JS/TS e só retorno por variável (o arquivo precisa citar
  `process.env`); ampliar quando um projeto Python/Elixir mostrar o mesmo padrão.
  """

  @arquivo ~r/\.(test|spec)\.[cm]?[jt]sx?\z/
  @teste ~r/\b(?:it|test)(?:\.\w+)?\s*\(/
  @retorno ~r/if\s*\(\s*!\s*[\w.$]+\s*\)\s*\{?\s*(?:[^{}]*?;\s*)?return\s*;/
  @assercao ~r/\b(?:expect|assert)\b/

  @doc "Arquivos de teste (relativos a `raiz`) que retornam cedo sem asserir."
  @spec detectar(Path.t(), [Path.t()]) :: [Path.t()]
  def detectar(raiz, arquivos) do
    Enum.filter(arquivos, fn rel ->
      case File.read(Path.join(raiz, rel)) do
        {:ok, texto} -> retorna_cedo?(texto)
        _ -> false
      end
    end)
  end

  @doc "Lista os arquivos de teste do worktree e aplica `detectar/2`."
  @spec detectar_no_worktree(Path.t()) :: [Path.t()]
  def detectar_no_worktree(raiz) do
    arquivos =
      raiz
      |> Path.join("**/*.{test,spec}.{js,jsx,ts,tsx,mjs,cjs,mts,cts}")
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, raiz))
      |> Enum.reject(&String.contains?(&1, "node_modules/"))
      |> Enum.filter(&Regex.match?(@arquivo, &1))

    detectar(raiz, arquivos)
  end

  @doc "O texto tem um teste que retorna antes de qualquer `expect`/`assert`?"
  @spec retorna_cedo?(String.t()) :: boolean()
  def retorna_cedo?(texto) do
    String.contains?(texto, "process.env") and
      texto
      |> String.split(@teste)
      |> tl()
      |> Enum.any?(fn corpo ->
        case Regex.run(@retorno, corpo, return: :index) do
          [{inicio, _}] -> not Regex.match?(@assercao, binary_part(corpo, 0, inicio))
          _ -> false
        end
      end)
  end
end
