---
paths:
  - "lib/engine/projects/**"
  - "lib/engine/session_events/**"
  - "lib/engine/outbox/**"
  - "priv/repo/**"
---

> Regra de CAMINHO: carregada só quando a sessão lê arquivo que casa com `paths:`. Saiu do `CLAUDE.md` por causa do teto de 40 mil caracteres; texto INTEGRAL de `.claude/contexto/convencoes-repositorio-e-dominio.md` (`brabo-legacy`, `dev` @ `1586158973`). Edite AQUI.

- O schema do Postgres mora em `apps/api/src/db/schema/`, UM arquivo por
  AGREGADO de domínio, espelhando `apps/api/src/domain/*` (ADR 0121);
  `db/schema.ts` é só o BARREL de `export *` que todo mundo importa, e é para
  onde `drizzle.config.ts` aponta. Tabela nova entra no arquivo do agregado
  dela — arquivo novo só quando o agregado é novo, e aí entra também no
  barrel, na posição do ASSUNTO e não no fim. Enum mora com a tabela que o
  CHAMA, não com o assunto: FK entre arquivos é segura num ciclo
  (`.references()` é callback preguiçoso), enum entre arquivos NÃO é (roda na
  avaliação do módulo) — o grafo de imports é um DAG e continuar assim é
  invariante que ninguém testa, só quebra no boot.

- Todo evento de domínio é imutável: nunca UPDATE em tabelas de eventos.

- O papel de PROJETO sobrepõe o de workspace nos DOIS sentidos —
  `ResolveEffectiveRoleUseCase.forProject` é `projectRole ?? workspaceRole`, e
  NÃO é "o maior dos dois" (RN-471). Restringir alguém num projeto sensível é
  capacidade deliberada; não "corrija" isso. O que a sobreposição não pode
  fazer são DOIS movimentos, e eles são teto (ADR 0127, RN-472): ninguém
  rebaixa quem é `owner` do WORKSPACE, e ninguém rebaixa a SI MESMO — 403 nos
  dois, sem chave de configuração. `owner` aqui é `workspace_members.role`,
  NUNCA `workspaces.created_by`: criador não é dono corrente, e o papel é o que
  a autorização usa em todo o resto do sistema. Os tetos moram no CASO DE USO
  com a regra pura em `domain/iam/tetos-de-rebaixamento.ts`, não no
  `RolesGuard` — o guard autoriza o CHAMADOR contra o `@RequireRole` da rota e
  não vê corpo nem alvo, e estes tetos são sobre o ALVO e sobre a relação
  ator↔alvo. O teto 2 vale por DUAS portas desde o ADR 0156 (RN-556): a
  REMOÇÃO da própria linha também é 403 quando o efeito líquido é rebaixamento
  — remover não apaga um papel, TROCA o efetivo pelo do workspace, que pode ser
  menor (ou não existir). `remocaoEhAutoRebaixamento` DELEGA a
  `ehAutoRebaixamento` passando o papel de workspace como o papel pedido — não
  escreva uma segunda régua. O teto 1 NÃO tem par na remoção, de propósito:
  `owner` é o topo do `ROLE_ORDER`, então tirar a linha de um `owner` de
  workspace só pode ELEVAR o efetivo dele, e é a única forma de desfazer a
  restrição que o teto 1 impede de criar. Desde o ADR 0157 (RN-557) o teto 2
  vale por QUATRO portas e nos DOIS SENTIDOS: `POST workspaces/:id/members`
  deixou de ser upsert sem teto (era passa-adiante sem ator, num escopo onde
  não há nível acima para segurar a queda — e, até o ADR 0173, nem rota que
  removesse membro), e a
  auto-PROMOÇÃO — que o ADR 0127 declarou como capacidade que ficava — é
  BRECHA e fecha, nas duas rotas de associação: é a única metade do movimento
  que ESCALA privilégio. A comparação virou UM classificador
  (`autoMovimentoDoProprioPapel`, devolve o SENTIDO porque a mensagem depende
  dele); `ehAutoRebaixamento` sobreviveu como LEITURA dele, de propósito — é
  por ela que `remocaoEhAutoRebaixamento` segue vendo só a metade de baixo, e
  alargá-la faria a REMOÇÃO recusar o movimento benigno que o ADR 0156
  protegeu. O teto 1 também NÃO tem par no workspace, e foi considerado, não
  espelhado: ele é regra sobre INVERSÃO DE HIERARQUIA, e o
  `@RequireRole('owner')` da rota já a impede — pô-lo faria de `owner` um
  estado absorvente, do qual ninguém sai por HTTP. E o teto NÃO conta owners:
  a cláusula já garante que um workspace nunca chega a zero, porque tirar o
  último exigiria que ele mesmo o fizesse. Desde o ADR 0173 (RN-615) há a
  QUINTA porta, `DELETE workspaces/:id/members/:userId` (`owner`, 204), e ela
  também não tem régua nova: é `remocaoEhAutoRebaixamento` com o papel de
  WORKSPACE como o efetivo de hoje e `null` como o de depois — no workspace
  não há nível acima, então remover a SI MESMO é sempre 403 (frase própria,
  `MENSAGEM_TETO_AUTO_REMOCAO_DO_WORKSPACE`). O ÚLTIMO owner fica protegido
  por essa MESMA cláusula, sem contagem: só `owner` chama a rota e ninguém se
  remove, então toda remoção deixa ao menos o chamador — o mínimo `owner` da
  rota é METADE da prova, e está asserido em teste; não o baixe. Remover OUTRO
  `owner` passa (é como se revoga propriedade), e o teto 1 segue sem par. A
  remoção CASCATEIA numa transação — as linhas de `project_members` do
  removido nos projetos do workspace (sem isso a sobreposição o manteria
  dentro), as chaves de dispositivo de PROJETO e os PATs dele ali — e depois
  derruba o runner vivo dele em cada projeto pelo caminho da RN-520, sem
  derrubar a remoção se o engine falhar. Fica de fora, declarado: chave de
  MÁQUINA, socket de sessão já conectado, terminal `:web`. O TITULAR
  (`workspaces.created_by`, de quem é a credencial que os agentes gastam,
  RN-058, e o relatório de gasto, RN-060) NÃO sai: 409 `criador_do_workspace`
  até `PUT workspaces/:id/owner-of-record` (`owner`, destino JÁ `owner`, senão
  409 `titular_precisa_ser_owner`) passar a titularidade (RN-616). Titular não
  é autorização — quem autoriza continua sendo o papel —, e a transferência
  não confere se o novo titular tem credencial: sem ela, o turno termina com o
  desfecho de sempre ("Nenhuma credencial cadastrada"). Não há tela de membros
  de workspace; as rotas são de API. A LEITURA (`GET workspaces/:id/members`,
  RN-655) é `viewer`, e não o `owner` das escritas: ler não é manter, e é por
  ela que o fio da sessão nomeia quem entra só pelo papel de workspace. Segue possível e declarado:
  rebaixar outro `maintainer`; um `owner` rebaixando OUTRO `owner` no
  workspace (única forma de revogar propriedade, reversível pela mesma rota);
  reescrever o próprio papel com o MESMO valor (upsert idempotente não é
  movimento); a auto-promoção pela REMOÇÃO da linha de projeto; e a
  auto-remoção quando o workspace segura o MESMO papel — essa é benigna e
  continua passando.
