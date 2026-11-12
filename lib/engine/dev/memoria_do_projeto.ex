defmodule Engine.Dev.MemoriaDoProjeto do
  @moduledoc """
  Leitor da memória do projeto (`.brabo/memoria/`, ADR 0293, AT-923): monta a
  mensagem FIXADA "Memória dos módulos" do kickoff e da correção do dev
  (RN-1110, RN-1111).

  Traz o cartão do módulo da tarefa, por inteiro, e dos módulos de que ele
  depende só `Expõe` e `Como usar`, mais o contrato declarado de cada um (lido
  do banco, a fonte única). Como a mensagem é `:pinned`, o `ContextManager`
  nunca a compacta, e o dev deixa de reler o que a compactação apagava.

  Orçamento de 8 000 tokens estimados. O módulo próprio é o último a ser
  cortado (pela cauda, com marcador); as seções de dependência que não cabem
  são omitidas e contadas, e o total real é dito (ADR 0060). O resto fica a um
  `read_file` de distância, e a mensagem diz o caminho.

  Cartão ausente (projeto antigo, primeira tarefa) ou pasta que o engine não vê
  (modo `runner`) não quebra nada: a mensagem diz isso.
  """

  alias Engine.Dev.MemoriaExtrator
  alias Engine.Harness.Tokenizer
  alias Engine.Sessions.EngineApiClient

  @orcamento_tokens 8_000
  # Folga para o cabeçalho e o aviso, que entram depois do corte: o total nunca passa do teto.
  @margem_tokens 250
  @secoes_da_dependencia ["Expõe", "Como usar"]

  @doc "Orçamento da mensagem, em tokens estimados."
  def orcamento_tokens, do: @orcamento_tokens

  @doc "Caminho relativo do cartão do módulo (nome saneado para arquivo)."
  def caminho_do_cartao(modulo),
    do: ".brabo/memoria/modulos/#{String.replace(modulo, ~r/[^\w.-]/u, "-")}.md"

  @doc "Pasta do módulo no worktree: `<worktree>/<modulo>` se existir, senão a raiz."
  def pasta_do_modulo(worktree, modulo) do
    pasta = Path.join(worktree, modulo)
    if File.dir?(pasta), do: pasta, else: worktree
  end

  @doc "`{modulos, versao}` do contrato declarado; falha da api vira `{[], nil}`."
  def contratos(project_id) do
    case EngineApiClient.list_module_contracts(project_id) do
      {:ok, %{"modulos" => modulos} = corpo} when is_list(modulos) ->
        {modulos, if(corpo["status"] == "declarados", do: corpo["version"])}

      _ ->
        {[], nil}
    end
  end

  @doc "A mensagem fixada. `modulos` e `versao` vêm de `contratos/1`."
  def mensagem(worktree, modulo, modulos, versao) do
    %{"role" => "user", "content" => texto(worktree, modulo, modulos, versao), :pinned => true}
  end

  @doc false
  def texto(worktree, modulo, modulos, versao) do
    meu = Enum.find(modulos, &(&1["modulo"] == modulo))
    cartao = ler_cartao(worktree, modulo)
    deps = if meu, do: meu["dependeDe"] || [], else: deps_do_cartao(cartao)

    {proprio, cortado?} =
      worktree
      |> bloco_proprio(modulo, cartao, meu, versao)
      |> truncar(@orcamento_tokens - @margem_tokens)

    blocos = Enum.map(deps, &bloco_de_dependencia(worktree, &1, modulos, versao))

    {dependencias, omitidas} =
      encaixar(blocos, @orcamento_tokens - @margem_tokens - Tokenizer.estimate(proprio))

    cabecalho =
      "Memória dos módulos (`.brabo/memoria/`, fixada: a compactação não a apaga). " <>
        "É o que o projeto sabe de cada módulo; leia daqui antes de explorar com `read_file`. " <>
        "Os outros módulos ficam em `.brabo/memoria/modulos/<módulo>.md`.\n\n"

    corpo = Enum.join([proprio | dependencias], "\n\n")
    aviso = aviso(cortado?, omitidas)
    total = Tokenizer.estimate(cabecalho <> corpo <> aviso)
    cabecalho <> corpo <> aviso <> "\n\n(~#{total} de #{@orcamento_tokens} tokens estimados.)"
  end

  # --- Blocos: {titulo, [{secao, corpo}]} ---

  defp bloco_proprio(worktree, modulo, cartao, meu, versao) do
    caminho = caminho_do_cartao(modulo)

    {nota, secoes} =
      case cartao do
        {:ok, secoes, _} ->
          {"", Enum.reject(secoes, fn {t, _} -> String.starts_with?(t, "Contrato declarado") end)}

        :ausente ->
          {"\nAinda não há memória deste módulo; o cartão nasce no seu `report_done`.", []}

        :indisponivel ->
          {"\nO engine não vê a pasta do projeto (#{worktree || "sem pasta"}); leia `#{caminho}` com `read_file`.",
           []}
      end

    "### Módulo `#{modulo}` (o da sua tarefa) — `#{caminho}`#{nota}" <>
      render(secoes ++ contrato(meu, versao))
  end

  defp bloco_de_dependencia(worktree, dep, modulos, versao) do
    do_cartao =
      case ler_cartao(worktree, dep) do
        {:ok, secoes, _} -> Enum.filter(secoes, fn {t, _} -> t in @secoes_da_dependencia end)
        _ -> []
      end

    mapa = Enum.find(modulos, &(&1["modulo"] == dep))

    {"### Dependência `#{dep}` — `#{caminho_do_cartao(dep)}`",
     do_cartao ++ contrato(mapa, versao)}
  end

  defp contrato(nil, _), do: []

  defp contrato(%{"expoe" => nil}, _), do: []

  defp contrato(mapa, versao) do
    [corpo] =
      mapa
      |> MemoriaExtrator.contrato_declarado(versao)
      |> String.split("\n\n", parts: 2)
      |> Enum.take(-1)

    [{if(versao, do: "Contrato declarado (v#{versao})", else: "Contrato declarado"), corpo}]
  end

  # Cada dependência entra seção a seção enquanto couber no que sobrou.
  defp encaixar(blocos, sobra) do
    {textos, _, omitidas} =
      Enum.reduce(blocos, {[], sobra, 0}, fn {titulo, secoes}, {acc, livre, omitidas} ->
        {ficam, livre, omitidas} =
          Enum.reduce(secoes, {[], livre - Tokenizer.estimate(titulo), omitidas}, fn secao,
                                                                                     {f, l, o} ->
            custo = Tokenizer.estimate(render([secao]))
            if custo <= l, do: {f ++ [secao], l - custo, o}, else: {f, l, o + 1}
          end)

        {acc ++ [titulo <> render(ficam)], livre, omitidas}
      end)

    {textos, omitidas}
  end

  defp render(secoes) when is_list(secoes),
    do: Enum.map_join(secoes, "", fn {t, corpo} -> "\n\n#### #{t}\n\n#{String.trim(corpo)}" end)

  defp render({titulo, secoes}), do: titulo <> render(secoes)

  defp truncar(texto, orcamento) do
    if Tokenizer.estimate(texto) <= orcamento do
      {texto, false}
    else
      corte = cortar_em_bytes(texto, orcamento * Tokenizer.bytes_per_token())
      {corte <> "\n(… cortado pelo orçamento)", true}
    end
  end

  # Corte por BYTES (é o que o estimador conta), sem deixar meio caractere UTF-8.
  defp cortar_em_bytes(texto, bytes) do
    corte = binary_part(texto, 0, bytes)
    if String.valid?(corte), do: corte, else: cortar_em_bytes(texto, bytes - 1)
  end

  defp aviso(false, 0), do: ""

  defp aviso(proprio?, omitidas) do
    partes =
      if(proprio?,
        do: ["o cartão do seu módulo foi cortado na cauda (leia-o inteiro com `read_file`)"],
        else: []
      ) ++
        if(omitidas > 0,
          do: [
            "#{omitidas} seção(ões) de dependências não coube(ram) (leia os cartões com `read_file`)"
          ],
          else: []
        )

    "\n\nCortado pelo orçamento: #{Enum.join(partes, "; ")}."
  end

  # --- Leitura do cartão ---

  # `{:ok, secoes, depende_de}` | `:ausente` | `:indisponivel` (pasta fora do alcance do engine).
  defp ler_cartao(worktree, modulo) do
    if is_binary(worktree) and File.dir?(worktree) do
      case File.read(Path.join(worktree, caminho_do_cartao(modulo))) do
        {:ok, texto} -> {:ok, secoes(texto), depende_de(texto)}
        _ -> :ausente
      end
    else
      :indisponivel
    end
  end

  defp deps_do_cartao({:ok, _, deps}), do: deps
  defp deps_do_cartao(_), do: []

  defp depende_de(texto) do
    case Regex.run(~r/^depende_de: \[(.*)\]$/m, texto) do
      [_, lista] -> lista |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
      _ -> []
    end
  end

  defp secoes(texto) do
    texto
    |> String.replace(~r/\A---\n.*?\n---\n/s, "")
    |> String.replace(MemoriaExtrator.marca_inicial(), "")
    |> String.replace(MemoriaExtrator.marca_final(), "")
    |> String.split(~r/^## /m)
    |> Enum.drop(1)
    |> Enum.map(fn s ->
      case String.split(s, "\n", parts: 2) do
        [titulo, corpo] -> {String.trim(titulo), corpo}
        [titulo] -> {String.trim(titulo), ""}
      end
    end)
  end
end
