defmodule Engine.Gates.ItensDoParecer do
  @moduledoc """
  AT-905 (RN-1116..1118): o parecer do QA separa o que BLOQUEIA (`itens`) do que
  é melhoria (`melhorias`), e a volta nova não move a régua. Puro, sem I/O.

  `itens` aceita string (compatibilidade) ou `{texto, origem}`, com `origem` em
  `anterior` | `regressao_no_diff`. Numa volta com pedido anterior, item
  `regressao_no_diff` só reprova se cita um arquivo alterado desde o head
  avaliado na volta anterior; sem isso vai para `melhorias`.
  """

  # O consolidador do QA Lead descarta o `resumo` do subagente, então o aviso
  # viaja no próprio texto da melhoria.
  @aviso " (movido: não trata de arquivo do diff desta volta, RN-1118)"

  @doc "Texto de um item, seja string ou `{texto, origem}`."
  @spec texto(term()) :: String.t()
  def texto(%{"texto" => t}), do: to_string(t)
  def texto(%{texto: t}), do: to_string(t)
  def texto(item), do: to_string(item)

  @doc "Itens como lista de strings (é o que a api e o artefato guardam)."
  @spec textos([term()]) :: [String.t()]
  def textos(itens), do: itens |> List.wrap() |> Enum.map(&texto/1)

  @doc """
  Aplica a régua da volta. Devolve o parecer com `itens` em texto e as
  `melhorias` acrescidas do que foi movido; se tudo foi movido e o parecer
  reprovava só por isso, vira `approved`.
  """
  @spec aplicar(map(), %{itens: [term()]} | nil, [String.t()] | nil) :: map()
  def aplicar(%{veredito: "changes_requested"} = parecer, anterior, arquivos_do_diff) do
    itens = List.wrap(parecer.itens)
    melhorias = textos(Map.get(parecer, :melhorias, []))

    {ficam, movidos} =
      if match?(%{itens: [_ | _]}, anterior) and is_list(arquivos_do_diff),
        do: Enum.split_with(itens, &(not regressao_fora_do_diff?(&1, arquivos_do_diff))),
        else: {itens, []}

    parecer =
      %{parecer | itens: textos(ficam)}
      |> Map.put(:melhorias, melhorias ++ Enum.map(textos(movidos), &(&1 <> @aviso)))

    if movidos != [] and ficam == [],
      do: %{parecer | veredito: "approved"},
      else: parecer
  end

  def aplicar(parecer, _anterior, _arquivos), do: Map.update(parecer, :itens, [], &textos/1)

  defp regressao_fora_do_diff?(item, arquivos) do
    origem = if is_map(item), do: Map.get(item, "origem") || Map.get(item, :origem)

    origem in ["regressao_no_diff", :regressao_no_diff] and
      not cita_arquivo?(texto(item), arquivos)
  end

  defp cita_arquivo?(texto, arquivos),
    do:
      Enum.any?(
        arquivos,
        &(String.contains?(texto, &1) or String.contains?(texto, Path.basename(&1)))
      )
end
