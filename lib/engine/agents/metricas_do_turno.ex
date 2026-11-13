defmodule Engine.Agents.MetricasDoTurno do
  @moduledoc """
  O custo, as chamadas, os tokens de raciocínio e a duração de UM turno de
  agente conversacional, como CAMPOS do `agent.response` de fecho (RN-1159,
  AT-933). Irmão de `RaciocinioDoTurno`: acumula no dicionário do processo do
  turno a cada chamada de LLM concluída (`registrar/1`, no ponto central de
  `EngineApiClient.llm_turn_stream/6`) e `descarregar/0` entrega ao fecho
  (`TextoDoTurno.payload_do_turno/2`), FORA do `content`.

  Campos: `custoMicros` (chat + Jev, como o orçamento do `ToolLoop`),
  `chamadasLlm`, `raciocinioTokens` (só quando algum `usage` o trouxe) e
  `duracaoMs` (da primeira chamada ao fecho; a latência da 1ª chamada, se o
  `usage` a trouxer, entra na conta).
  """

  alias Engine.Harness.RoteamentoDeFerramenta

  @chave {__MODULE__, :acumulo}

  @doc "Soma uma chamada de LLM concluída ao turno."
  @spec registrar(map()) :: :ok
  def registrar(resp) when is_map(resp) do
    usage = if is_map(resp["usage"]), do: resp["usage"], else: %{}
    agora = System.monotonic_time(:millisecond)
    latencia = if is_integer(usage["latencyMs"]), do: usage["latencyMs"], else: 0

    a =
      Process.get(@chave) ||
        %{inicio: agora - latencia, custo: 0, chamadas: 0, raciocinio: nil}

    raciocinio =
      case usage["reasoningTokens"] do
        n when is_integer(n) -> (a.raciocinio || 0) + n
        _ -> a.raciocinio
      end

    custo = (usage["costMicros"] || 0) + RoteamentoDeFerramenta.custo_micros(resp)

    Process.put(@chave, %{
      a
      | custo: a.custo + custo,
        chamadas: a.chamadas + 1,
        raciocinio: raciocinio
    })

    :ok
  end

  def registrar(_), do: :ok

  @doc "Entrega os campos do turno (ou `%{}` sem chamada) e esvazia o acúmulo."
  @spec descarregar() :: map()
  def descarregar do
    case Process.delete(@chave) do
      nil ->
        %{}

      a ->
        base = %{
          custoMicros: a.custo,
          chamadasLlm: a.chamadas,
          duracaoMs: System.monotonic_time(:millisecond) - a.inicio
        }

        if a.raciocinio, do: Map.put(base, :raciocinioTokens, a.raciocinio), else: base
    end
  end
end
