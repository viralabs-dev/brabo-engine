defmodule Engine.Agents.RaciocinioDoTurno do
  @moduledoc """
  O RACIOCÍNIO do modelo ao longo do turno (AT-676, RN-993): irmão de
  `FontesDoTurno`. Acumula, no dicionário do processo do turno, o
  `raciocinio` INTEIRO de cada chamada de LLM e o entrega ao fecho
  (`TextoDoTurno.payload_do_turno/2` e o `ToolLoop`) como `raciocinio` e
  `raciocinioTotal` (caracteres), FORA do `content`.

  NUNCA volta ao modelo: `Reidratacao` não lê estas chaves, e o RAG não indexa.
  Os `thinkingBlocks` da Anthropic ficam só em memória, entre as voltas do
  laço, e são devolvidos em CADA mensagem `assistant` com `toolCalls` do turno,
  cada uma com os seus (RN-1013) — nunca vão ao log.
  """

  @chave {__MODULE__, :textos}
  @chave_blocos {__MODULE__, :blocos}

  @doc "Guarda o raciocínio (e os blocos da Anthropic) de uma chamada concluída."
  @spec registrar(map()) :: :ok
  def registrar(resp) when is_map(resp) do
    case resp["raciocinio"] do
      t when is_binary(t) and t != "" -> Process.put(@chave, [t | Process.get(@chave, [])])
      _ -> :ok
    end

    with [_ | _] = blocos <- get_in(resp, ["message", "thinkingBlocks"]),
         id when not is_nil(id) <- primeira_chamada(resp) do
      Process.put(@chave_blocos, Map.put(Process.get(@chave_blocos, %{}), id, blocos))
    end

    :ok
  end

  def registrar(_), do: :ok

  defp primeira_chamada(resp) do
    case get_in(resp, ["message", "toolCalls"]) do
      [%{"id" => id} | _] -> id
      _ -> nil
    end
  end

  @doc """
  Devolve a CADA mensagem `assistant` com `toolCalls` os blocos da chamada que a
  gerou (casados pelo id da 1ª `toolCall`), para o prefixo só crescer (RN-1013).
  """
  @spec anexar_blocos([map()]) :: [map()]
  def anexar_blocos(messages) do
    blocos = Process.get(@chave_blocos, %{})

    Enum.map(messages, fn
      %{"role" => "assistant", "toolCalls" => [%{"id" => id} | _]} = m ->
        case blocos do
          %{^id => b} -> Map.put(m, "thinkingBlocks", b)
          _ -> m
        end

      m ->
        m
    end)
  end

  @doc "Entrega `%{raciocinio, raciocinioTotal}` (ou `%{}`) e esvazia o acúmulo."
  @spec descarregar() :: map()
  def descarregar do
    Process.delete(@chave_blocos)

    case Process.delete(@chave) do
      nil ->
        %{}

      textos ->
        texto = textos |> Enum.reverse() |> Enum.join("\n\n")
        %{raciocinio: texto, raciocinioTotal: String.length(texto)}
    end
  end
end
