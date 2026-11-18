defmodule Engine.Agents.LoteDisjunto do
  @moduledoc """
  RN-1380 (AT-991): o módulo pode ter N agentes quando há N tarefas independentes
  (sem `depende_de` entre si) com `arquivos` disjuntos. Conferência pura, glob contra glob.
  """

  @doc "`tarefas`: `[%{id, titulo, arquivos, deps}]`. `:ok` ou `{:error, frase}`."
  @spec conferir([map()], pos_integer()) :: :ok | {:error, String.t()}
  def conferir(tarefas, agentes) do
    {lote, ultimo_conflito} =
      Enum.reduce(tarefas, {[], nil}, fn t, {lote, conf} ->
        case Enum.find_value(lote, &conflito(&1, t)) do
          nil -> {lote ++ [t], conf}
          c -> {lote, c}
        end
      end)

    cond do
      length(lote) >= agentes -> :ok
      ultimo_conflito -> {:error, ultimo_conflito}
      true -> {:error, "só #{length(lote)} tarefa(s) levantada(s) nele."}
    end
  end

  defp conflito(a, b) do
    cond do
      b.id in a.deps or a.id in b.deps ->
        "\"#{a.titulo}\" e \"#{b.titulo}\" dependem uma da outra."

      par = comum(a.arquivos, b.arquivos) ->
        {x, y} = par
        "\"#{a.titulo}\" e \"#{b.titulo}\" dividem arquivo: #{x} / #{y}."

      true ->
        nil
    end
  end

  defp comum(as, bs), do: Enum.find_value(for(x <- as, y <- bs, do: {x, y}), &se_sobrepoem/1)

  # shortcut: compara só o trecho fixo antes do primeiro curinga; pode ver
  # sobreposição que o glob completo não tem (recusa a mais, nunca a menos).
  defp se_sobrepoem({x, y}) do
    {bx, by} = {base(x), base(y)}
    if List.starts_with?(bx, by) or List.starts_with?(by, bx), do: {x, y}
  end

  defp base(glob),
    do: glob |> Path.split() |> Enum.take_while(&(not String.contains?(&1, ["*", "?", "[", "{"])))
end
