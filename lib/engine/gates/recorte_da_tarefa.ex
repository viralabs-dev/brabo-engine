defmodule Engine.Gates.RecorteDaTarefa do
  @moduledoc """
  O recorte da TAREFA que o gate de QA julga (AT-448, RN-765).

  O QA recebia só a história inteira e reprovava a tarefa por um RF que é de
  uma tarefa IRMÃ ainda pendente ("login HTTP com JWT não existe nesta
  entrega" na tarefa que só modelava a tabela) — e a tarefa bloqueava depois
  de três correções que ela não tinha como fazer. Este módulo monta o texto
  que a QA-estratégia e a QA-automação recebem: título e descrição da tarefa,
  as regras de negócio da história, e as tarefas irmãs com o status (o que
  `GET .../dev-context` devolve em `siblingTasks`) e, desde a AT-461 (RN-785),
  as tarefas não concluídas de OUTRAS histórias do mesmo módulo
  (`moduleOpenTasks`). A régua é dita junto: o
  veredito é sobre o que é DESTA tarefa, e requisito de outra tarefa é
  OBSERVAÇÃO, nunca reprovação. Puro — sem I/O.
  """

  @doc "Texto do recorte, a partir de `dev_context` (`task`, `sibling_tasks`, regras)."
  @spec texto(map()) :: String.t()
  def texto(dev_context) do
    task = Map.get(dev_context, :task, %{})
    irmas = Map.get(dev_context, :sibling_tasks, [])
    regras = Map.get(dev_context, :business_rules_units, [])
    abertas = Map.get(dev_context, :module_open_tasks, [])
    total = Map.get(dev_context, :module_open_tasks_total, length(abertas))
    decisoes = Map.get(dev_context, :decisoes, [])
    decisoes_do_projeto = Map.get(dev_context, :decisoes_do_projeto, [])

    """

    RECORTE DESTA TAREFA (o veredito é sobre ele):
    Tarefa: #{Map.get(task, "title", "")}
    #{Map.get(task, "description", "")}

    Regras de negócio da história:
    #{lista(Enum.map(regras, &Map.get(&1, :content, "")))}

    Outras tarefas da MESMA história (não são desta entrega):
    #{lista(Enum.map(irmas, &irma/1))}

    Tarefas ainda NÃO concluídas de OUTRAS histórias do mesmo módulo:
    #{lista(Enum.map(abertas, &aberta/1))}#{corte(abertas, total)}

    Julgue SÓ o que é desta tarefa. Requisito da história que pertence a
    outra tarefa (feita ou pendente) NÃO reprova esta entrega: cite-o no
    `resumo` como observação e não o ponha em `itens`. O mesmo vale para o
    que depende de entrega de OUTRA história ainda não feita (uma rota, uma
    tela, um dado que ela cria): é observação, nunca reprovação.

    Liste em `itens` TODAS as lacunas desta tarefa que você achar nesta volta,
    de uma vez — nunca uma por volta: cada volta é uma correção paga e um passo
    do teto do ciclo. Antes de emitir, faça a VARREDURA POR REGRA: percorra
    cada regra de negócio acima e cada critério da tarefa, um por um, e para
    cada um diga a si mesmo onde está a prova (arquivo e teste) ou que ela
    falta. Só emita depois de passar por TODAS; lacuna que já estava na
    entrega e aparece só na volta seguinte é uma volta paga a mais.
    Na varredura, confira também que o usuário usa pelo README DA PASTA DO
    MÓDULO desta tarefa (AT-903, RN-1122; o README da raiz é da Infra e da
    tarefa de integração, e rota que só estiver nele não é exigida nem reprova):
    rota HTTP criada ou mudada nesta tarefa tem ali método, caminho, corpo, respostas e
    códigos, dentro da seção "Rotas HTTP" (antes de "Testes", nunca no fim), o README não traz nota de processo nem instrução para
    agentes, e erro de entrada responde com mensagem própria do projeto, nunca
    a crua da biblioteca; o que faltar vai a `itens`.

    Separe `itens` de `melhorias` (AT-905, RN-1116): `itens` é SÓ o que viola
    regra da história, critério da tarefa ou regra deste recorte; o resto
    (estilo, nome, cobertura extra, ideia) é `melhorias` e não reprova. Regra
    sem prova nunca é melhoria (AT-1023, RN-1513).

    Requisito marcado "não confirmado pelo usuário" (ou contradito por decisão
    vigente) → `needs_user_decision`, nunca `changes_requested`: mande a
    `pergunta` e a sua `sugestao`. ANTES de `needs_user_decision`, confira as
    decisões listadas abaixo: requisito que uma delas já responde NÃO é
    pergunta — aplique a decisão. `openQuestionId` só com o uuid de uma
    pergunta ABERTA; sem esse uuid, a pergunta nova vai em
    `pergunta`/`sugestao`.
    #{Engine.Dev.ContextBuilder.secao_de_decisoes(decisoes)}#{Engine.Dev.ContextBuilder.secao_de_decisoes_do_projeto(decisoes_do_projeto)}    #{secao_do_ambiente_limpo()}#{secao_dos_testes_sem_prova(dev_context)}#{secao_da_decisao_na_matriz(decisoes)}#{secao_do_clone_limpo(Map.get(dev_context, :clone_limpo))}#{secao_da_prova_do_entregavel(dev_context)}#{criterios_da_entrega(dev_context)}
    """
  end

  @doc """
  Os criterios da entrega, sem a regua do veredito (AT-905, RN-1134): o QA os
  recebe em `texto/1` e o dev no kickoff e na correcao. UMA funcao gera os dois.
  """
  @spec criterios_da_entrega(map()) :: String.t()
  def criterios_da_entrega(dev_context) do
    task = Map.get(dev_context, :task, %{})
    regras = Map.get(dev_context, :business_rules_units, [])

    secao_da_forma(regras, task) <>
      secao_do_ponto_de_entrada(task, dev_context) <>
      secao_do_contrato(Map.get(dev_context, :module_contract))
  end

  # AT-479 (RN-765): a regra dizia "a contagem e o histórico
  # de cliques de TODOS os links" e o QA aprovou `{totalCliques}`, sem a
  # contagem POR link. Quando o texto da regra quantifica por item ("por X",
  # "cada", "de todos os"), o recorte pede a conferência da FORMA da resposta.
  # Só um lembrete de leitura: não muda a régua do veredito (a regra continua
  # sendo a que reprova). A recusa que não nomeia o campo é OBSERVAÇÃO.
  @quantificador ~r/\b(de tod[oa]s [oa]s|cada|por (?!exemplo|padr[aã]o|isso|meio|favor|causa|vez|cento|enquanto|fim|ora)\p{L}+)/iu

  defp secao_da_forma(regras, task) do
    textos = [Map.get(task, "description", "") | Enum.map(regras, &Map.get(&1, :content, ""))]

    if Enum.any?(textos, &(is_binary(&1) and Regex.match?(@quantificador, &1))),
      do: """

      Forma da resposta: há regra que fala POR item ("por X", "cada", "de
      todos os"). Confira no código/teste que a resposta traz o valor de CADA
      item (ex.: uma contagem por link), não só o total — total sozinho não
      cobre a regra. E quando uma entrada é recusada, veja se a mensagem nomeia
      o campo recusado; se não nomeia, cite no `resumo` como observação (não
      vai para `itens`, salvo regra que o exija).
      """,
      else: ""
  end

  # AT-483 (RN-813): no TP-01 o `server.ts` nunca chamava a migração e uma rota
  # `/:code` sombreava `GET /links` — os 53 testes passavam porque cada um monta
  # o próprio app. Quando a tarefa toca o ponto de entrada, a fiação ou o README
  # de execução, o recorte exige evidência de que o entrypoint REAL sobe e
  # responde; a ausência dela vai para `itens`.
  # RN-865 (AT-527): "endpoint" e verbo HTTP com caminho também são rota. No
  # TP-01 as tarefas de `POST /links` e `GET /panel` diziam só "Endpoint
  # protegido", a régua não casava, e nem o dev recebeu a cláusula do OpenAPI
  # nem o QA a conferência — as duas rotas ficaram fora do `/openapi.json`.
  @ponto_de_entrada ~r/(server\.[jt]s|main\.[jt]s|index\.[jt]s|entrypoint|ponto de entrada|app\.listen|\bREADME|npm start|pnpm start|\bstart\b|\bfia[cç][aã]o|\bmigra[cç][aã]o|\brotas?\b|\broutes?\b|\bendpoints?\b|\b(GET|POST|PUT|PATCH|DELETE)\s+\/)/iu

  @doc """
  A tarefa toca ponto de entrada, fiação ou rotas? Régua ÚNICA, usada pelo
  recorte do QA (RN-813/854) e pelo kickoff do dev (RN-853).
  """
  @spec toca_ponto_de_entrada?(map()) :: boolean()
  def toca_ponto_de_entrada?(task) when is_map(task) do
    texto = "#{Map.get(task, "title", "")} #{Map.get(task, "description", "")}"
    Regex.match?(@ponto_de_entrada, texto)
  end

  def toca_ponto_de_entrada?(_), do: false

  @doc """
  AT-1016 (RN-1515): a tarefa é de OUTRO módulo que não o que sobe o app? Só então a
  prova do app de pé deixa de ser dela. Sem o campo da api (ou sem módulo na tarefa),
  é falso e vale a régua de antes. Régua ÚNICA: o recorte do QA e o kickoff do dev.
  """
  @spec de_outro_modulo_que_o_do_app?(map(), map()) :: boolean()
  def de_outro_modulo_que_o_do_app?(task, dev_context) do
    modulo = Map.get(dev_context, :modulo_do_ponto_de_entrada)
    dono = if is_map(task), do: Map.get(task, "module")

    is_binary(modulo) and is_binary(dono) and dono != modulo and
      not Map.get(dev_context, :esqueleto_do_app, false)
  end

  defp secao_do_ponto_de_entrada(task, dev_context) do
    cond do
      not toca_ponto_de_entrada?(task) -> ""
      de_outro_modulo_que_o_do_app?(task, dev_context) -> secao_da_suite_do_modulo(dev_context)
      true -> secao_do_app_de_pe()
    end
  end

  defp secao_da_suite_do_modulo(dev_context) do
    """

    Ponto de entrada: o app inteiro sobe pelo módulo `#{dev_context.modulo_do_ponto_de_entrada}`, não por este.
    Aqui a prova da rota é a SUÍTE do módulo, com um teste que monta o
    registrador/plugin do módulo numa instância do framework (ex.: `inject`) e
    responde na rota. Não exija o app de pé, o `start` da raiz nem o
    `/openapi.json` servido: isso é observação no `resumo`, nunca item (RN-1515).
    O que é da rota continua item: cada rota da seção "Rotas HTTP" do README do
    módulo precisa existir no código que a registra (e o contrário), e o mesmo
    caso de erro responde o mesmo `code` em todas as rotas do módulo.
    """
  end

  defp secao_do_app_de_pe do
    """

    Ponto de entrada: esta tarefa toca o entrypoint, a fiação (rotas,
    migração, registro) ou o README de execução. Exija evidência de que o
    ponto de entrada REAL sobe — o `start`/`main` do projeto rodado, ou um
    teste que importe o entrypoint real (não um app montado no próprio
    teste) — e responde numa rota ou comando. O ponto de entrada que precisa
    subir é o da APLICAÇÃO (o `run.app`/compose declarado pela Infra), não o
    `start` de cada módulo: módulo que o contrato diz ser composto por outro
    (dependência injetada) não precisa subir sozinho, e exigir isso é
    observação no `resumo`, nunca item (AT-909, RN-1119). Teste que monta o próprio
    banco e o próprio app não prova isso. Sem essa evidência, ponha a lacuna
    em `itens`.

    O que CONTA como evidência no ambiente do dev: subir o processo do
    entrypoint (o `start`/`main`) na pasta do projeto, rodar o script no
    container do projeto, bater numa rota do processo de pé. O que NÃO cabe
    ali: construir imagem Docker, rodar o `docker compose up` de verdade,
    rede externa — o container do projeto não tem Docker nem saída
    garantida. Exigência desse segundo tipo NUNCA vai para `itens`: cite-a
    no `resumo` como observação. A instalação, o build, a suíte e a subida a
    partir do zero NÃO são desse tipo: quando há "Clone limpo" abaixo, são
    itens (AT-921, RN-1121).

    OpenAPI e Swagger (RN-854, ADR 0213): suba o app pelo comando do README
    em background DENTRO da instância de QA (não o app de trabalho, que fica
    como está; os serviços de `run.qa.services` estão no `localhost` dela), bata em
    `localhost:<porta interna>/openapi.json` e `/docs` (a imagem não traz
    `curl`: use `node -e "fetch(...).then(...)"`; em projeto que não é Node,
    a ferramenta HTTP que ela tem, `command -v curl wget node python3`) e encerre o GRUPO de processos ao fim. Rota que
    não responde, ou JSON que não é OpenAPI 3, vai a `itens`. Cada rota da
    seção "Rotas HTTP" do README do módulo da tarefa precisa estar em `paths` do `/openapi.json`
    servido (com o método), e também cada rota que o CÓDIGO registra
    (procure o registro de rotas, ex.: `app.get(`, `app.post(`, `router.`):
    rota faltando é ITEM, nunca observação. O
    build da imagem e o `docker compose up` real NÃO são seus: na última
    tarefa do projeto e na fundação do esqueleto do app o engine pede a prova ao broker, no servidor (ADR 0297,
    RN-1330), e ela entra no parecer sozinha; sem broker o parecer aprova com
    o aviso "sem prova de compose". Não o exija em `itens`.

    URL, erro e CORS (RN-879/880): URL absoluta devolvida pela API (ex.: um
    link curto) sai de `PUBLIC_BASE_URL` ou do `Host` da requisição COM a
    porta; `http://localhost` fixo ou hostname sem porta é ITEM. O mesmo caso
    de erro (ex.: recurso inexistente) responde o mesmo `code` em todas as
    rotas; divergência (ex.: `not_found` numa, `link_not_found` noutra) é
    ITEM. Prove CORS (RN-885) com um preflight contra a porta PUBLICADA
    (`APP_PORT` do compose, nunca a interna `PORT`), uma vez para cada
    origem, `http://localhost:<APP_PORT>` e `http://127.0.0.1:<APP_PORT>`
    (`node -e "fetch(url, {method: 'OPTIONS', headers: {Origin: '<origem>',
    'Access-Control-Request-Method': 'POST'}}).then(r => console.log(r.status,
    [...r.headers]))"`): cada resposta precisa de
    `OPTIONS` 204 E do header `Access-Control-Allow-Origin` com a origem
    enviada, além dos `Access-Control-Allow-*` (com `Authorization` e
    `Content-Type`); 204 sem esse header, ou CORS só na porta interna, é ITEM. `servers` com URL ABSOLUTA no
    `/openapi.json`, ou swagger-ui de CDN sem versão exata (ex.: `@5`), é ITEM.
    """
  end

  # AT-496 (RN-817): no TP-01 a suíte travava num clone limpo (um teste matava
  # o `npm` e o `node` neto ficava na 3000), e o QA viu exit 0 porque o teste
  # se PULAVA com a porta ocupada por um servidor órfão de rodada anterior. O
  # recorte pede estado limpo antes da suíte, teste de processo que encerre o
  # GRUPO, e teste pulado por ambiente como observação. É instrução e não passo
  # do harness: quem roda a suíte é o próprio QA pelo `terminal`, que já passa
  # pela política e pelo roteamento de container dos três modos.
  defp secao_do_ambiente_limpo do
    """

    Ambiente limpo (AT-612): seu `terminal` roda numa INSTÂNCIA DE QA própria
    do projeto, que sobe para este gate e some depois. Antes de rodar a suíte,
    encerre o que o PRÓPRIO QA deixou de pé nela (servidor do `start` ainda
    escutando numa porta) — só processos desta pasta, ex.: `pkill -f` com o
    caminho do projeto, e só lá. O app de trabalho do projeto (o app declarado
    pela Infra, em outro container) nunca é tocado. Os serviços que a Infra
    declarou (`run.qa.services`: banco, S3 e afins) já estão de pé no
    `localhost` da instância, com as variáveis `env` que ela declarou; use-os
    em vez de simulá-los. Teste que sobe processo
    deve encerrar o GRUPO (ou subir `node` direto, não via `npm`, que deixa o
    neto vivo); se não encerra, a suíte trava num clone limpo — é lacuna em
    `itens`. Teste PULADO (`skip` ou retorno antecipado por ambiente:
    porta ocupada, ferramenta ou variável ausente) não cobre a regra: a linha
    dela na matriz é `covered: false`, e só `motivo: aceito_pelo_dono` deixa
    aprovar assim. Nunca é `melhoria` (AT-1023, RN-1513).
    """
  end

  # AT-1023 (RN-1513): retorno antecipado por ambiente é teste que não prova nada.
  defp secao_dos_testes_sem_prova(%{testes_sem_prova: [_ | _] = arquivos}),
    do: """

    Estes testes retornam cedo sem asserção e NÃO provam nada (AT-1023): #{Enum.join(arquivos, ", ")}.
    Regra que só eles cobrem é `covered: false`.
    """

  defp secao_dos_testes_sem_prova(_), do: ""

  defp secao_da_decisao_na_matriz([_ | _]),
    do: """

    Decisão do dono (AT-1023): cada decisão listada acima para esta tarefa é uma
    linha da `coverageMatrix` (`rule: "Decisão do dono: <pergunta> → <resposta>"`),
    `covered: true` só se o que ela pede está feito e provado nesta volta. Se ela
    aceita deixar um teste pulado, a linha da regra dele leva `motivo:
    "aceito_pelo_dono"`. Se pede algo que outro agente não fez (ex.: a Infra não
    declarou o banco), NÃO aprove e NÃO use `melhorias`: reprove com o item «a
    decisão do dono "<…>" ainda não foi cumprida (origem: infra)».
    """

  defp secao_da_decisao_na_matriz(_), do: ""

  # AT-921 (RN-1121): o clone limpo do commit sob revisão, preparado pelo engine.
  # Sem `:clone_limpo` (a régua de disparo não casou), a seção não existe.
  defp secao_do_clone_limpo({:ok, pasta}),
    do: """

    Clone limpo (AT-921): o engine preparou `#{pasta}/` com o commit sob
    revisão (`git archive HEAD`: sem `node_modules`, `dist` nem arquivo não
    versionado). DENTRO dele, rode os passos de instalação e build que o
    Dockerfile do módulo de entrada (ou o README) declara (ex.: `npm ci` na
    raiz e o build do workspace), depois a suíte, e suba o `run.app` e
    confira `/docs` e `/openapi.json` (`node -e "fetch(...)"`, sem `curl`), encerrando o GRUPO de
    processos ao fim. Falha em qualquer passo é ITEM (instalar, compilar,
    testar e subir é a prova que o worktree do dev não dá). Falha de REDE
    (registry inacessível) tem origem `infra`: cite no `resumo`, nunca em
    `itens`. Sem Docker e sem LLM extra.
    """

  defp secao_do_clone_limpo({:indisponivel, motivo}),
    do: """

    Clone limpo indisponível (#{motivo}): cite no `resumo`; isso não reprova.
    """

  defp secao_do_clone_limpo(_), do: ""

  # AT-982 (RN-1350): na ÚLTIMA tarefa do projeto, com o clone limpo, o QA
  # exercita por HTTP o fluxo das regras do PROJETO (a api manda
  # `regrasDoProjeto` só nesse caso); o recorte só traz as da história.
  defp secao_da_prova_do_entregavel(%{ultima_do_projeto: true, clone_limpo: {:ok, pasta}} = ctx) do
    regras =
      ctx
      |> Map.get(:regras_do_projeto, [])
      |> Enum.map_join("\n", &"- #{Map.get(&1, "title")}: #{Map.get(&1, "description")}")

    """

    Prova do entregável (última tarefa do projeto, AT-982): DENTRO de `#{pasta}/`,
    siga o README da raiz (copie `.env.example` para `.env` se ainda não
    existir, instale, compile e suba o app em background) e exercite POR HTTP
    (`node -e "fetch(...)"`, a imagem não traz `curl`) cada regra do projeto
    abaixo: o caminho feliz e a recusa que a regra define, com o status
    esperado, incluindo o primeiro acesso de cada papel. Rota 404, resposta 500
    ou regra violada é ITEM; falha de rede do registry tem origem `infra`
    (`resumo`, nunca `itens`). Encerre o GRUPO de processos ao fim.
    #{if regras == "", do: "(A api não mandou regras do projeto: prove o fluxo pelo README.)", else: "Regras do projeto:\n" <> regras}
    """
  end

  defp secao_da_prova_do_entregavel(_), do: ""

  # AT-462 (RN-786): o contrato do Arquiteto é a fonte da INTERFACE (nome de
  # rota, assinatura). O dev o segue; divergência com a história é do
  # Arquiteto/usuário resolverem, não do dev.
  defp secao_do_contrato(%{"expoe" => [_ | _] = itens} = c) do
    """

    Contrato do módulo #{Map.get(c, "modulo", "")} (declarado pelo Arquiteto — a fonte da INTERFACE):
    #{lista(Enum.map(itens, &item_do_contrato/1))}

    Quando a história e o contrato divergem num nome de interface (rota,
    função, evento), a entrega que segue o CONTRATO não é reprovada por isso:
    nomeie a DIVERGÊNCIA no `resumo` (história diz X, contrato diz Y) como
    observação para o usuário e o Arquiteto, fora de `itens`. O mesmo vale
    para a EXECUÇÃO (AT-909, RN-1119): se o contrato diz que este módulo é
    composto por outro (dependência injetada por quem compõe), exigir que ele
    suba sozinho não é item; cite a divergência no `resumo`.
    """
  end

  defp secao_do_contrato(_), do: ""

  defp item_do_contrato(i),
    do:
      "#{Map.get(i, "tipo", "")}: #{Map.get(i, "assinatura", "")} — #{Map.get(i, "descricao", "")}"

  defp aberta(t),
    do:
      "#{Map.get(t, "title", "")} (#{Map.get(t, "status", "?")}, história: #{Map.get(t, "storyTitle", "?")})"

  defp corte(abertas, total) when total > length(abertas),
    do: "\n(mostrando #{length(abertas)} de #{total})"

  defp corte(_, _), do: ""

  defp irma(t), do: "#{Map.get(t, "title", "")} (#{Map.get(t, "status", "?")})"

  defp lista([]), do: "(nenhuma)"
  defp lista(itens), do: Enum.map_join(itens, "\n", &("- " <> to_string(&1)))
end
