defmodule Engine.Dev.ExplicacaoDoBloqueio do
  @moduledoc """
  AT-1021 (RN-1529): toda tarefa bloqueada leva uma EXPLICAÇÃO para quem não
  programa — `causa` (uma frase) e 1..2 `acoes` prontas (`rotulo` +
  `orientacao`), que o web transforma em botões de retomada em um clique.

  Dois autores, uma só forma:
  - o SISTEMA (os pontos de bloqueio determinísticos) tira a explicação do
    catálogo por código, `de/1`;
  - o AGENTE a escreve em `report_blocked`, e `do_agente/2` valida a regra de
    linguagem para o modelo reescrever (o molde do `declare_open_question`).

  A regra de linguagem vale para `causa` e `rotulo` — nunca para `orientacao`
  (instrução ao dev) nem para o diagnóstico técnico. A api repete a mesma regra
  na fronteira (descarta a explicação inválida, o bloqueio acontece).

  Forma enviada à api: `%{codigo?, causa, acoes: [%{id?, rotulo, orientacao}]}`.
  """

  @teto_causa 160
  @teto_rotulo 40
  @teto_orientacao 2_000

  # Regra de linguagem para leigo (AT-1021). Cada par é {motivo, regex}.
  @proibidos [
    {"UUID", ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i},
    {"hash hexadecimal", ~r/\b[0-9a-f]{12,}\b/i},
    {"crase", ~r/`/},
    {"nome de arquivo", ~r/\w+\.(json|lock|ts|js|ex|exs|yml|yaml|md|sql|env)\b/},
    {"caminho", ~r{/\w+/}},
    {"identificador com ponto", ~r/\b[a-z]+(\.[a-z]+){2,}\b/i},
    {"identificador snake_case", ~r/\b[a-z0-9]+(_[a-z0-9]+)+\b/i},
    {"identificador camelCase", ~r/\b[a-z]+[A-Z][A-Za-z]*\b/},
    {"átomo", ~r/(^|[\s\[(,]):[a-z_]\w*/},
    {"constante", ~r/\b[A-Z]{2,}_[A-Z0-9_]+\b/},
    {"código de erro", ~r/\bE[A-Z]{5,}\b/},
    {"host:porta", ~r/\b[\w.\-]+:\d{2,5}\b/},
    {"código HTTP", ~r/\b[1-5]\d{2}\b/}
  ]

  @tentar_de_novo %{id: "tentar_de_novo", rotulo: "Tentar de novo", orientacao: ""}

  defp tentar(orientacao \\ ""), do: %{@tentar_de_novo | orientacao: orientacao}

  # codigo => {causa, acoes}. Função (não atributo): `tentar/1` é privada.
  defp catalogo do
    %{
      reinicio_do_engine:
        {"O sistema foi reiniciado enquanto a tarefa estava em andamento.", [tentar()]},
      falha_de_contexto:
        {"Não foi possível reunir as informações da tarefa para o agente continuar.", [tentar()]},
      push_nao_aprovado:
        {"O envio do trabalho ao repositório não foi aprovado, então a tarefa parou.",
         [
           tentar(
             "O envio foi negado antes; refaça o commit e o envio, e peça a aprovação de novo."
           )
         ]},
      push_falhou:
        {"Não foi possível enviar o trabalho ao repositório do projeto.",
         [tentar("Tente enviar de novo; se falhar outra vez, descreva o erro do envio.")]},
      commit_recusado:
        {"O commit ou o envio da correção foi recusado, então a tarefa parou.",
         [tentar("Refaça o commit da correção e o envio, e confira o resultado de cada um.")]},
      pr_nao_aberta:
        {"A PR não foi aberta porque as ações de git da tarefa não foram aprovadas.",
         [tentar("Proponha de novo o commit, o envio e a abertura da PR.")]},
      retomada_da_branch:
        {"Não foi possível retomar a branch da PR que está em conflito.", [tentar()]},
      conflito_de_integracao:
        {"O trabalho entrou em conflito com a versão mais nova do projeto e o agente não o resolveu.",
         [
           tentar(
             "Integre a main atual na branch, resolva todos os conflitos e só então conclua a tarefa."
           )
         ]},
      conflito_de_merge:
        {"A PR ficou em conflito com a versão mais nova do projeto e nenhum agente pôde resolvê-lo.",
         [tentar()]},
      credencial_de_git:
        {"A chave de acesso ao repositório não pode ser usada nesta máquina de execução.",
         [tentar()]},
      falha_no_worktree: {"Não foi possível preparar a pasta de trabalho da tarefa.", [tentar()]},
      worktree_diverge:
        {"A pasta de trabalho e a branch publicada estão em versões diferentes.", [tentar()]},
      orcamento_excedido:
        {"O limite de gasto desta tarefa foi atingido, e só você pode liberar mais.",
         [
           %{
             id: "aumentar_o_teto",
             rotulo: "Aumentar o teto e continuar",
             orientacao: ""
           }
         ]},
      limite_de_iteracoes:
        {"O agente usou todas as tentativas da tarefa sem conseguir concluir.",
         [
           tentar("Recomece pela causa do último erro e conclua a tarefa com poucas mudanças.")
         ]},
      limite_de_iteracoes_correcao:
        {"O agente usou todas as tentativas da correção sem conseguir concluí-la.",
         [tentar("Recomece pela causa do último erro e corrija só o que o gate apontou.")]},
      credito_do_provedor:
        {"O crédito do provedor do modelo acabou, então o agente parou.",
         [tentar("O crédito foi reposto; continue a tarefa de onde parou.")]},
      limite_de_uso:
        {"O provedor do modelo atingiu o limite de uso e o agente precisou parar.", [tentar()]},
      falha_de_rede:
        {"A conexão com o provedor do modelo caiu; a tarefa volta sozinha em alguns minutos.",
         [tentar()]},
      resposta_cortada:
        {"O modelo gastou todo o espaço da resposta pensando e não chegou a agir.", [tentar()]},
      parada_sem_sinal:
        {"O agente parou sem concluir a tarefa e sem dizer o motivo.", [tentar()]},
      qa_instancia_indisponivel:
        {"A QA de Automação não conseguiu subir o ambiente de teste.", [tentar()]},
      qa_espera_esgotada: {"O ambiente de teste demorou demais para ficar pronto.", [tentar()]},
      gate_bloqueado: {"A verificação da tarefa parou antes de dar o parecer.", [tentar()]},
      sessao_encerrada:
        {"A sessão de execução foi encerrada com a tarefa em andamento.",
         [tentar("A sessão voltou; retome a tarefa a partir da branch dela.")]},
      generico: {"O agente parou e precisa de você para continuar.", [tentar()]}
    }
  end

  @doc "Códigos do catálogo (átomos)."
  def codigos, do: Map.keys(catalogo())

  @doc """
  A explicação do bloqueio do sistema por código: `%{codigo, causa, acoes}`.
  Código desconhecido é erro de programação (`FunctionClauseError`).
  """
  def de(codigo) when is_atom(codigo) do
    {causa, acoes} = Map.fetch!(catalogo(), codigo)
    %{codigo: Atom.to_string(codigo), causa: causa, acoes: acoes}
  end

  @doc "`:ok` ou `{:error, motivo}` da regra de linguagem para leigo."
  def frase_para_leigo(texto, max \\ @teto_causa)

  def frase_para_leigo(texto, max) when is_binary(texto) do
    t = String.trim(texto)

    cond do
      t == "" -> {:error, "vazio"}
      String.length(t) > max -> {:error, "passa de #{max} caracteres"}
      String.contains?(t, ". ") or String.contains?(t, "\n") -> {:error, "mais de uma frase"}
      true -> achar_proibido(t)
    end
  end

  def frase_para_leigo(_, _), do: {:error, "precisa ser texto"}

  @doc "Só os padrões da regra de linguagem (sem teto nem 'uma frase'): `:ok` ou `{:error, motivo}`."
  def sem_jargao(texto) when is_binary(texto), do: achar_proibido(texto)

  defp achar_proibido(t) do
    case Enum.find(@proibidos, fn {_, re} -> Regex.match?(re, t) end) do
      nil -> :ok
      {motivo, _} -> {:error, "tem #{motivo}"}
    end
  end

  @doc """
  Valida a explicação escrita pelo agente (argumentos do `report_blocked`).
  `{:ok, %{causa, acoes}}` ou `{:error, texto}` para o modelo reescrever.
  """
  def do_agente(causa, acoes) do
    with :ok <- checar("causa_para_leigo", causa, @teto_causa),
         {:ok, acoes} <- acoes_do_agente(acoes) do
      {:ok, %{causa: String.trim(causa), acoes: acoes}}
    end
  end

  defp acoes_do_agente([_ | _] = acoes) when length(acoes) <= 2 do
    Enum.reduce_while(acoes, {:ok, []}, fn acao, {:ok, acc} ->
      with %{} <- acao,
           rotulo = Map.get(acao, "rotulo"),
           orientacao = Map.get(acao, "orientacao"),
           :ok <- checar("acoes[].rotulo", rotulo, @teto_rotulo),
           true <- orientacao_valida?(orientacao) do
        {:cont,
         {:ok, acc ++ [%{rotulo: String.trim(rotulo), orientacao: String.trim(orientacao)}]}}
      else
        {:error, _} = erro ->
          {:halt, erro}

        _ ->
          {:halt,
           {:error, "`acoes[].orientacao` exige texto de 1 a #{@teto_orientacao} caracteres"}}
      end
    end)
  end

  defp acoes_do_agente(_), do: {:error, "`acoes` exige 1 ou 2 ações {rotulo, orientacao}"}

  defp orientacao_valida?(o),
    do: is_binary(o) and String.trim(o) != "" and String.length(o) <= @teto_orientacao

  @doc """
  AT-1021: até 2 `opcoes` prontas de uma pergunta (`rotulo` na regra de linguagem,
  `resposta` livre). `nil`/ausente é `{:ok, nil}`; recusa é `{:error, texto}` para o modelo.
  """
  def opcoes(nil), do: {:ok, nil}
  def opcoes([]), do: {:ok, nil}

  def opcoes(lista) when is_list(lista) and length(lista) <= 2 do
    Enum.reduce_while(lista, {:ok, []}, fn o, {:ok, acc} ->
      with %{} <- o,
           rotulo = Map.get(o, "rotulo"),
           resposta = Map.get(o, "resposta"),
           :ok <- checar("opcoes[].rotulo", rotulo, @teto_rotulo),
           true <- orientacao_valida?(resposta) do
        {:cont,
         {:ok, acc ++ [%{"rotulo" => String.trim(rotulo), "resposta" => String.trim(resposta)}]}}
      else
        {:error, _} = erro ->
          {:halt, erro}

        _ ->
          {:halt,
           {:error, "`opcoes[].resposta` exige texto de 1 a #{@teto_orientacao} caracteres"}}
      end
    end)
  end

  def opcoes(_), do: {:error, "`opcoes` aceita no máximo 2 opções {rotulo, resposta}"}

  @doc "AT-1021: `detalhe` técnico opcional (até #{@teto_orientacao} caracteres, texto livre)."
  def detalhe(nil), do: {:ok, nil}

  def detalhe(d) when is_binary(d) do
    d = String.trim(d)

    cond do
      d == "" ->
        {:ok, nil}

      String.length(d) > @teto_orientacao ->
        {:error, "`detalhe` passa de #{@teto_orientacao} caracteres"}

      true ->
        {:ok, d}
    end
  end

  def detalhe(_), do: {:error, "`detalhe` precisa ser texto"}

  defp checar(campo, valor, max) do
    case frase_para_leigo(valor, max) do
      :ok ->
        :ok

      {:error, motivo} ->
        {:error,
         "`#{campo}` fora da regra de linguagem (#{motivo}): escreva uma frase curta para quem " <>
           "não programa, sem nome de arquivo, caminho, identificador, código de erro ou crase"}
    end
  end
end
