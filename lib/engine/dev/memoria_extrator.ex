defmodule Engine.Dev.MemoriaExtrator do
  @moduledoc """
  Escreve o cartão do módulo em `.brabo/memoria/modulos/<m>.md` (RN-1112,
  RN-1113, RN-1114; ADR 0293, AT-923). MECÂNICO: leitura de arquivo e regex,
  sem LLM, sem rede, sem Node.

  Roda no `report_done` do dev, ANTES do commit, para o cartão entrar na mesma
  PR, passar pelos gates e chegar à `main` junto com o código. Cobre TS/Node
  (`package.json`, exports do ponto de entrada, rotas por regex ou
  `openapi.json`, migrações). Pasta sem `package.json` sai só com a lista de
  arquivos e a seção humana.

  O cartão tem duas partes:

    * a GERADA, entre `<!-- brabo:gerado -->` e `<!-- /brabo:gerado -->`, que
      é sobrescrita a cada chamada, sem timestamp (o mesmo código gera o mesmo
      arquivo);
    * a HUMANA, "Como usar", depois do marcador final. Só muda pelo
      `como_usar` do dev do módulo; sem ele, o que já estava lá fica.

  O contrato declarado vem do banco (fonte única, RN-684) e é só renderizado,
  com a divergência contrato × código dita nos dois sentidos, nunca corrigida
  em silêncio.

  Limite conhecido (shortcut): a rota é o caminho como está escrito no arquivo,
  sem o prefixo de `app.use('/api', router)`; passar a seguir `use` quando o
  `openapi.json` não bastar.
  """

  alias Engine.Dev.MemoriaDoProjeto
  alias Engine.Harness.RotasDoContrato

  @inicio "<!-- brabo:gerado -->"
  @fim "<!-- /brabo:gerado -->"
  @sem_como_usar "_(ainda não escrito pelo dev do módulo)_"
  @como_usar_max_bytes 4_000
  @max_fontes 400
  @max_bytes_por_fonte 200_000
  @teto_lista 40
  @fora ~w(.git node_modules .brabo dist build coverage .next out __tests__ test tests)
  @extensoes ~w(.ts .tsx .mts .js .jsx .mjs .cjs)
  @pastas_de_migracao ~w(migrations db/migrations src/migrations prisma/migrations drizzle)

  @re_decl ~r/^\s*export\s+(?:declare\s+)?(?:async\s+)?(function\*?|abstract\s+class|class|const|let|var|interface|type|enum)\s+([A-Za-z_$][\w$]*)/m
  @re_lista ~r/^\s*export\s+(?:type\s+)?\{([^}]*)\}/m
  @re_default ~r/^\s*export\s+default\b/m
  @re_estrela ~r/^\s*export\s+\*\s+from\s+['"]([^'"]+)['"]/m
  @re_cjs_obj ~r/module\.exports\s*=\s*\{([^}]*)\}/
  @re_cjs_prop ~r/^\s*(?:module\.)?exports\.([A-Za-z_$][\w$]*)\s*=/m
  @re_rota ~r/\b(?:app|router|server|fastify|api|route|routes|r)\.(get|post|put|patch|delete)\s*\(\s*(['"`])(\/[^'"`]*)\2/i
  @re_funcao ~r/^\s*([A-Za-z_$][\w$.]*)\s*\(/

  @doc "Caminho do marcador inicial da parte gerada (usado pelo leitor)."
  def marca_inicial, do: @inicio

  @doc "Marcador final da parte gerada."
  def marca_final, do: @fim

  @doc """
  Gera e grava o cartão do `modulo` no `worktree`. `opts`:

    * `:como_usar` — texto do dev para a seção humana (opcional);
    * `:contrato` — o mapa do módulo em `list_module_contracts` (`"expoe"`,
      `"dependeDe"`), ou `nil`;
    * `:versao` — a versão do contrato declarado;
    * `:commit` — SHA da base, opcional.

  `{:ok, caminho_relativo}`, ou `:ignorado` com pasta que o engine não vê
  (modo `runner`) ou módulo sem nome.
  """
  def escrever(worktree, modulo, opts \\ []) do
    if is_binary(worktree) and File.dir?(worktree) and is_binary(modulo) and modulo != "" do
      rel = MemoriaDoProjeto.caminho_do_cartao(modulo)
      abs = Path.join(worktree, rel)
      existente = File.read(abs) |> ler_ok()

      conteudo =
        worktree
        |> MemoriaDoProjeto.pasta_do_modulo(modulo)
        |> extrair()
        |> cartao(modulo, existente, opts)

      if existente != conteudo do
        File.mkdir_p!(Path.dirname(abs))
        File.write!(abs, conteudo)
      end

      apontar_na_raiz(worktree)
      {:ok, rel}
    else
      :ignorado
    end
  end

  # --- Extração ---

  @doc "O que o código da pasta `dir` expõe (mapa, sem I/O de escrita)."
  def extrair(dir) do
    pacote = ler_pacote(dir)
    fontes = fontes(dir)
    entrada = entrada(dir, pacote)

    %{
      stack: stack(pacote, fontes),
      pacote: pacote,
      entrada: entrada,
      expoe: if(entrada, do: exports_da_entrada(dir, entrada), else: []),
      exportados_em_qualquer_lugar:
        fontes |> Enum.flat_map(&nomes_exportados(elem(&1, 1))) |> MapSet.new(),
      texto_das_fontes: Enum.map_join(fontes, "\n", &elem(&1, 1)),
      rotas: rotas(dir, fontes),
      migracoes: migracoes(dir),
      arquivos: if(pacote == nil, do: lista_de_arquivos(dir), else: [])
    }
  end

  defp ler_pacote(dir) do
    with {:ok, texto} <- File.read(Path.join(dir, "package.json")),
         {:ok, %{} = mapa} <- Jason.decode(texto) do
      mapa
    else
      _ -> nil
    end
  end

  defp fontes(dir) do
    dir
    |> caminhos(dir, 0)
    |> Enum.filter(fn rel ->
      Path.extname(rel) in @extensoes and not String.contains?(rel, [".test.", ".spec."])
    end)
    |> Enum.take(@max_fontes)
    |> Enum.flat_map(fn rel ->
      case File.read(Path.join(dir, rel)) do
        {:ok, bin} when byte_size(bin) <= @max_bytes_por_fonte ->
          if String.valid?(bin), do: [{rel, bin}], else: []

        _ ->
          []
      end
    end)
  end

  # Caminhos relativos (ordenados) de arquivos regulares, sem as pastas de @fora.
  defp caminhos(dir, raiz, profundidade) when profundidade < 8 do
    case File.ls(dir) do
      {:ok, entradas} ->
        entradas
        |> Enum.sort()
        |> Enum.flat_map(fn nome ->
          abs = Path.join(dir, nome)

          cond do
            nome in @fora -> []
            File.dir?(abs) -> caminhos(abs, raiz, profundidade + 1)
            File.regular?(abs) -> [Path.relative_to(abs, raiz)]
            true -> []
          end
        end)

      _ ->
        []
    end
  end

  defp caminhos(_, _, _), do: []

  defp lista_de_arquivos(dir), do: dir |> caminhos(dir, 0) |> Enum.take(@teto_lista)

  defp stack(nil, _), do: "desconhecida"

  defp stack(_pacote, fontes) do
    if Enum.any?(fontes, fn {rel, _} -> Path.extname(rel) in ~w(.ts .tsx .mts) end),
      do: "node-ts",
      else: "node"
  end

  defp entrada(_dir, nil), do: nil

  defp entrada(dir, pacote) do
    declarados =
      [pacote["main"], ponto_de_exports(pacote["exports"]), pacote["module"], pacote["types"]]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim_leading(&1, "./"))

    derivados = Enum.flat_map(declarados, &fonte_de/1)

    (derivados ++
       declarados ++ ~w(src/index.ts src/index.js index.ts index.js src/main.ts src/app.ts))
    |> Enum.find(&File.regular?(Path.join(dir, &1)))
  end

  defp ponto_de_exports(s) when is_binary(s), do: s
  defp ponto_de_exports(%{"." => v}), do: ponto_de_exports(v)

  defp ponto_de_exports(%{} = m) do
    Enum.find_value(~w(import default require types), &ponto_de_exports(m[&1]))
  end

  defp ponto_de_exports(_), do: nil

  # `dist/x.js` → `src/x.ts`: o ponto de entrada de verdade é o fonte.
  defp fonte_de(rel) do
    base =
      Regex.replace(~r/^(dist|build|lib)\//, rel, "src/")
      |> String.replace(~r/\.(c|m)?js$/, "")
      |> String.replace(~r/\.d\.ts$/, "")

    [base <> ".ts", base <> ".tsx"]
  end

  defp exports_da_entrada(dir, entrada) do
    texto = File.read(Path.join(dir, entrada)) |> ler_ok()

    proprios = itens_de_export(texto)

    seguidos =
      @re_estrela
      |> Regex.scan(texto)
      |> Enum.flat_map(fn [_, destino] ->
        destino |> resolver(dir, entrada) |> itens_do_arquivo(dir)
      end)

    Enum.uniq(proprios ++ seguidos)
  end

  # `export * from './x'`: um nível, `.js` do ESM resolve para o `.ts` do fonte.
  defp resolver("." <> _ = destino, dir, entrada) do
    base = dir |> Path.join(Path.dirname(entrada)) |> Path.join(destino) |> Path.expand()
    sem_js = String.replace(base, ~r/\.(c|m)?js$/, "")

    [
      base,
      sem_js <> ".ts",
      sem_js <> ".tsx",
      sem_js <> ".js",
      sem_js <> "/index.ts",
      sem_js <> "/index.js"
    ]
    |> Enum.find(&File.regular?/1)
  end

  defp resolver(_, _, _), do: nil

  defp itens_do_arquivo(nil, _dir), do: []
  defp itens_do_arquivo(abs, _dir), do: abs |> File.read() |> ler_ok() |> itens_de_export()

  defp itens_de_export(texto) do
    declarados =
      for [_, tipo, nome] <- Regex.scan(@re_decl, texto), do: {tipo_legivel(tipo), nome}

    listados = for nome <- nomes_da_lista(texto, @re_lista, :apelido), do: {"export", nome}

    padrao = if Regex.match?(@re_default, texto), do: [{"default", "default"}], else: []

    cjs =
      for(nome <- nomes_da_lista(texto, @re_cjs_obj, :chave), do: {"export", nome}) ++
        for [_, nome] <- Regex.scan(@re_cjs_prop, texto), do: {"export", nome}

    Enum.uniq(declarados ++ listados ++ padrao ++ cjs)
  end

  defp nomes_exportados(texto), do: texto |> itens_de_export() |> Enum.map(&elem(&1, 1))

  # `{ a as b }` exporta `b` (:apelido); `{ a: 1 }` exporta `a` (:chave).
  defp nomes_da_lista(texto, regex, modo) do
    regex
    |> Regex.scan(texto)
    |> Enum.flat_map(fn [_, corpo] -> String.split(corpo, ",") end)
    |> Enum.map(fn item ->
      item
      |> String.split(~r/\s+as\s+|:/, trim: true)
      |> then(fn partes -> if modo == :chave, do: List.first(partes), else: List.last(partes) end)
      |> to_string()
      |> String.replace(~r/^\s*type\s+/, "")
      |> String.trim()
    end)
    |> Enum.filter(&Regex.match?(~r/^[A-Za-z_$][\w$]*$/, &1))
  end

  defp tipo_legivel("function" <> _), do: "função"
  defp tipo_legivel("class"), do: "classe"
  defp tipo_legivel("abstract" <> _), do: "classe"
  defp tipo_legivel(t) when t in ~w(const let var), do: "valor"
  defp tipo_legivel(t) when t in ~w(interface type), do: "tipo"
  defp tipo_legivel(t), do: t

  defp rotas(dir, fontes) do
    do_codigo =
      for {_, texto} <- fontes, [_, metodo, _, caminho] <- Regex.scan(@re_rota, texto) do
        {String.upcase(metodo), caminho}
      end

    (do_codigo ++ rotas_do_openapi(dir))
    |> Enum.uniq_by(&normalizada/1)
    |> Enum.sort()
  end

  defp rotas_do_openapi(dir) do
    ~w(openapi.json docs/openapi.json public/openapi.json)
    |> Enum.find_value([], fn rel ->
      with {:ok, texto} <- File.read(Path.join(dir, rel)),
           {:ok, %{"paths" => %{} = paths}} <- Jason.decode(texto) do
        for {caminho, %{} = operacoes} <- paths,
            {metodo, _} <- operacoes,
            metodo in ~w(get post put patch delete),
            do: {String.upcase(metodo), caminho}
      else
        _ -> nil
      end
    end)
  end

  defp normalizada({metodo, caminho}),
    do: List.first(RotasDoContrato.extrair("#{metodo} #{caminho}"))

  defp migracoes(dir) do
    Enum.find_value(@pastas_de_migracao, [], fn pasta ->
      abs = Path.join(dir, pasta)

      case File.ls(abs) do
        {:ok, [_ | _] = nomes} -> nomes |> Enum.sort() |> Enum.map(&Path.join(pasta, &1))
        _ -> nil
      end
    end)
  end

  # --- Cartão ---

  defp cartao(achados, modulo, existente, opts) do
    contrato = Keyword.get(opts, :contrato)
    depende_de = depende_de(achados.pacote, contrato)

    [
      front_matter(modulo, achados.stack, depende_de, Keyword.get(opts, :commit)),
      "# Módulo #{modulo}\n\n",
      @inicio,
      "\n",
      secao("Expõe", expoe(achados)),
      secao("Scripts", scripts(achados.pacote)),
      secao("Depende de", Enum.map(depende_de, &"- `#{&1}`")),
      secao("Migrações", Enum.map(achados.migracoes, &"- `#{&1}`")),
      contrato_declarado(contrato, Keyword.get(opts, :versao)),
      divergencia(contrato, achados),
      @fim,
      "\n\n",
      humana(existente, Keyword.get(opts, :como_usar))
    ]
    |> IO.iodata_to_binary()
  end

  defp front_matter(modulo, stack, depende_de, commit) do
    linhas =
      ["modulo: #{modulo}", "stack: #{stack}", "depende_de: [#{Enum.join(depende_de, ", ")}]"] ++
        if(commit, do: ["commit: #{commit}"], else: [])

    "---\n#{Enum.join(linhas, "\n")}\n---\n"
  end

  defp depende_de(pacote, contrato) do
    do_contrato = List.wrap(contrato && contrato["dependeDe"])

    # Dependência local (`file:`/`workspace:`/`link:`) é pacote irmão.
    irmaos =
      for {nome, versao} <- Map.merge(map(pacote, "dependencies"), map(pacote, "devDependencies")),
          is_binary(versao) and String.starts_with?(versao, ["file:", "workspace:", "link:"]),
          do: nome

    (do_contrato ++ Enum.sort(irmaos)) |> Enum.uniq()
  end

  defp map(nil, _), do: %{}
  defp map(pacote, chave), do: if(is_map(pacote[chave]), do: pacote[chave], else: %{})

  defp expoe(%{pacote: nil, arquivos: arquivos}),
    do: ["_(linguagem sem extrator: só a lista de arquivos)_" | Enum.map(arquivos, &"- `#{&1}`")]

  defp expoe(%{expoe: itens, rotas: rotas, entrada: entrada}) do
    exports = for {tipo, nome} <- Enum.take(itens, @teto_lista), do: "- `#{nome}` (#{tipo})"
    sobra = length(itens) - length(Enum.take(itens, @teto_lista))
    cabecalho = if entrada, do: ["Ponto de entrada: `#{entrada}`"], else: []

    cabecalho ++
      exports ++
      if(sobra > 0, do: ["- (+#{sobra} não mostrados)"], else: []) ++
      for {metodo, caminho} <- Enum.take(rotas, @teto_lista),
          do: "- `#{metodo} #{caminho}` (rota)"
  end

  defp scripts(nil), do: []

  defp scripts(pacote) do
    for {nome, comando} <- Enum.sort(map(pacote, "scripts")),
        is_binary(comando),
        do: "- `#{nome}`: `#{comando}`"
  end

  @doc "Seção Contrato declarado (vN) renderizada do banco (fonte única, RN-684)."
  def contrato_declarado(nil, _),
    do: secao("Contrato declarado", ["(sem contrato declarado para este módulo)"])

  def contrato_declarado(contrato, versao) do
    titulo = if versao, do: "Contrato declarado (v#{versao})", else: "Contrato declarado"

    itens =
      for i <- List.wrap(contrato["expoe"]) do
        descricao =
          if is_binary(i["descricao"]) and i["descricao"] != "",
            do: " — #{i["descricao"]}",
            else: ""

        "- [#{i["tipo"]}] #{i["assinatura"]}#{descricao}"
      end

    secao(titulo, itens)
  end

  defp divergencia(nil, _), do: ""

  defp divergencia(contrato, achados) do
    itens = List.wrap(contrato["expoe"])

    funcoes =
      for i <- itens, i["tipo"] == "funcao", nome = identificador(i["assinatura"]), do: nome

    rotas_declaradas = Enum.flat_map(itens, &rotas_do_contrato(&1["assinatura"]))
    normalizadas_declaradas = Enum.map(rotas_declaradas, &normalizada/1)

    rotas_do_codigo = Enum.map(achados.rotas, &normalizada/1)

    ausentes =
      for nome <- Enum.uniq(funcoes),
          not MapSet.member?(achados.exportados_em_qualquer_lugar, nome),
          not Regex.match?(
            ~r/(?<![\w$])#{Regex.escape(nome)}(?![\w$])/,
            achados.texto_das_fontes
          ),
          do: "- `#{nome}()` está no contrato e não existe no código"

    rotas_ausentes =
      for {m, c} = rota <- rotas_declaradas,
          normalizada(rota) not in rotas_do_codigo,
          do: "- `#{m} #{c}` está no contrato e o código não serve"

    fora_do_contrato =
      if funcoes == [] do
        []
      else
        for {tipo, nome} <- achados.expoe,
            tipo in ~w(função classe valor),
            nome not in funcoes,
            do: "- `#{nome}` o código exporta e o contrato não declara"
      end

    rotas_fora =
      if rotas_declaradas == [] do
        []
      else
        for {m, c} = rota <- achados.rotas,
            normalizada(rota) not in normalizadas_declaradas,
            do: "- `#{m} #{c}` o código serve e o contrato não declara"
      end

    linhas = Enum.take(ausentes ++ rotas_ausentes ++ fora_do_contrato ++ rotas_fora, @teto_lista)

    secao(
      "Divergência contrato × código",
      if(linhas == [], do: ["(nenhuma divergência encontrada)"], else: linhas)
    )
  end

  # `{método, caminho como escrito}`: o cartão mostra o caminho do contrato, não o normalizado.
  defp rotas_do_contrato(assinatura) when is_binary(assinatura) do
    for [_, m, c] <-
          Regex.scan(~r/\b(GET|POST|PUT|PATCH|DELETE)\s+(\/[^\s"'`,;()\[\]<>]*)/, assinatura),
        do: {m, c}
  end

  defp rotas_do_contrato(_), do: []

  defp identificador(assinatura) when is_binary(assinatura) do
    case Regex.run(@re_funcao, assinatura) do
      [_, nome] -> nome |> String.split(".") |> List.last()
      _ -> nil
    end
  end

  defp identificador(_), do: nil

  defp secao(_titulo, []), do: ""
  defp secao(titulo, linhas), do: "## #{titulo}\n\n#{Enum.join(linhas, "\n")}\n\n"

  # A parte humana: o que já estava depois do marcador final, a menos que o dev
  # mande `como_usar`, que troca SÓ a seção.
  defp humana(existente, como_usar) do
    novo = if is_binary(como_usar), do: String.trim(como_usar), else: ""

    corpo =
      cond do
        novo != "" -> "## Como usar\n\n" <> limitar(novo) <> "\n"
        true -> humana_existente(existente)
      end

    corpo
  end

  defp humana_existente(existente) do
    case existente && String.split(existente, @fim, parts: 2) do
      [_, resto] ->
        if String.trim(resto) == "", do: sem_como_usar(), else: String.trim_leading(resto)

      _ ->
        sem_como_usar()
    end
  end

  defp sem_como_usar, do: "## Como usar\n\n#{@sem_como_usar}\n"

  defp limitar(texto) when byte_size(texto) <= @como_usar_max_bytes, do: texto

  defp limitar(texto) do
    String.slice(texto, 0, @como_usar_max_bytes) <>
      "\n(… cortado: o `como_usar` passou de #{@como_usar_max_bytes} bytes; o texto inteiro tinha #{byte_size(texto)})"
  end

  # --- Ponteiro no AGENTS.md da raiz (ADR 0293) ---

  @ponteiro "A memória do projeto está em `.brabo/memoria/` (um cartão por módulo, em `modulos/<m>.md`): leia o do seu módulo antes de explorar."

  defp apontar_na_raiz(worktree) do
    abs = Path.join(worktree, "AGENTS.md")
    atual = File.read(abs) |> ler_ok()

    unless String.contains?(atual, ".brabo/memoria") do
      separador = if atual == "" or String.ends_with?(atual, "\n"), do: "", else: "\n"
      File.write!(abs, atual <> separador <> "\n" <> @ponteiro <> "\n")
    end
  end

  defp ler_ok({:ok, texto}), do: texto
  defp ler_ok(_), do: ""
end
