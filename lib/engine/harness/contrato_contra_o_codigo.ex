defmodule Engine.Harness.ContratoContraOCodigo do
  @moduledoc """
  Confere o contrato do Arquiteto contra o CÓDIGO mergeado e aponta as
  tarefas que a mudança de contrato deixou velhas (RN-1093, RN-1094, AT-918).

  No TP-01 de 09/11/2026 os contratos descreviam `roteadorX(db)` que 4 dos 5
  módulos não tinham, e o contrato mudado não tocava as tarefas já criadas.
  Determinístico, sem LLM e sem recusa (contrato pode declarar interface
  FUTURA): o texto volta no resultado de `declare_module_contracts` e o
  Arquiteto age. A pasta do projeto é a `main` mergeada (RN-1021).
  """

  alias Engine.Harness.RotasDoContrato
  alias Engine.Harness.WorkspaceFiles

  @teto 10
  @funcao ~r/^\s*([A-Za-z_$][\w$.]*)\s*\(/
  @fora ~w(done cancelled canceled archived)

  @doc """
  Linhas das funções declaradas que a pasta `root` não contém. `root` nulo ou
  vazio (modo `runner`: a pasta está na máquina do usuário) diz que não conferiu.
  """
  def texto_do_codigo(contratos, root) do
    if is_binary(root) and File.dir?(root) and WorkspaceFiles.count(root) > 0 do
      ausentes =
        contratos
        |> Enum.flat_map(fn c ->
          for i <- Map.get(c, :expoe, []),
              Map.get(i, :tipo) == "funcao",
              nome = identificador(Map.get(i, :assinatura, "")),
              ausente?(root, nome),
              do: "- `#{nome}` (módulo `#{Map.get(c, :modulo)}`) não existe hoje na main"
        end)
        |> Enum.uniq()

      lista(
        "O CONTRATO cita código que a main não tem",
        ausentes,
        "Declare o que o código expõe (read_file/search_workspace) ou crie a tarefa que o implementa."
      )
    else
      "\n\n(Não conferi o código: a pasta do projeto não está visível ao engine, como no modo runner.)"
    end
  end

  @doc """
  Linhas das tarefas não concluídas que citam interface (função ou rota) que a
  versão anterior tinha e a nova mudou ou tirou. `anteriores` vem de
  `list_module_contracts` (chaves string), `novos` é a lista normalizada,
  `backlog` a árvore de `list_backlog`.
  """
  def texto_das_tarefas(anteriores, novos, backlog) do
    retiradas = MapSet.difference(tokens(anteriores, "assinatura"), tokens(novos, :assinatura))

    afetadas =
      for epico <- List.wrap(backlog),
          historia <- List.wrap(Map.get(epico, "stories")),
          tarefa <- List.wrap(Map.get(historia, "tasks")),
          Map.get(tarefa, "status") not in @fora,
          is_nil(Map.get(tarefa, "archivedAt")),
          citadas = Enum.filter(retiradas, &cita?(tarefa, &1)),
          citadas != [],
          do:
            "- tarefa #{Map.get(tarefa, "id")} \"#{Map.get(tarefa, "title")}\" cita " <>
              Enum.map_join(Enum.sort(citadas), ", ", &"`#{&1}`")

    lista(
      "TAREFAS afetadas pela mudança do contrato",
      afetadas,
      "Corrija cada uma com update_task agora; se não fizerem mais sentido, arquive-as " <>
        "(ferramenta de arquivar tarefa, quando houver no seu catálogo)."
    )
  end

  defp ausente?(root, nome), do: elem(WorkspaceFiles.search(root, nome, max_hits: 1), 0) == []

  defp identificador(assinatura) do
    case Regex.run(@funcao, assinatura) do
      [_, nome] -> nome |> String.split(".") |> List.last()
      _ -> nil
    end
  end

  # Identificador de função (antes do `(`) ou rota `MÉTODO /caminho`, como texto.
  defp tokens(contratos, chave) do
    for c <- List.wrap(contratos),
        i <- List.wrap(c[mapa_expoe(c)]),
        a = i[chave] || "",
        t <-
          Enum.filter(
            [identificador(a) | for({m, p} <- RotasDoContrato.extrair(a), do: "#{m} #{p}")],
            & &1
          ),
        into: MapSet.new(),
        do: t
  end

  defp mapa_expoe(c), do: if(Map.has_key?(c, :expoe), do: :expoe, else: "expoe")

  defp cita?(tarefa, token) do
    texto = Enum.join([tarefa["title"], tarefa["description"]], "\n")

    if String.contains?(token, " "),
      do: token in Enum.map(RotasDoContrato.extrair(texto), fn {m, p} -> "#{m} #{p}" end),
      else: Regex.match?(~r/(?<![\w$])#{Regex.escape(token)}(?![\w$])/, texto)
  end

  defp lista(_titulo, [], _orientacao), do: ""

  defp lista(titulo, linhas, orientacao) do
    {mostradas, resto} = Enum.split(linhas, @teto)

    "\n\n#{titulo} (#{length(linhas)}):\n" <>
      Enum.join(mostradas, "\n") <>
      if(resto == [], do: "", else: "\n- (+#{length(resto)} não mostradas)") <>
      "\n" <> orientacao
  end
end
