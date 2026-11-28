defmodule Engine.Harness.FalaParaLeigo do
  @moduledoc """
  A orientação de "fala para leigo" (RN-1533, AT-1026): o usuário do Brabo não
  programa, então nenhuma resposta ou pergunta a ele mostra identificador
  interno (UUID, `questionId`, hash) nem número de máquina (similaridade,
  limiar, código de saída). O id continua nas ferramentas e no texto do turno;
  só não vai para a fala.

  Mensagem `role: "system"` EFÊMERA, no molde do `IdiomaDaResposta`: a fachada
  `Engine.Sessions.EngineApiClient` a acrescenta a cada chamada de LLM, nunca
  em `state.messages`. Só os conversacionais (`Engine.Agents.Conversacionais`):
  dev agents e gates escrevem código, PR e parecer, onde o id é o assunto.
  """

  @texto "Ao falar com o usuário, cite tarefa, pergunta, regra, ADR ou PR pelo título. " <>
           "Nunca escreva identificador interno (UUID, questionId, taskId, hash) nem número de " <>
           "máquina (similaridade, limiar, código de saída). O id é só para as ferramentas. " <>
           "Não cite nome de ferramenta sua (o usuário não as vê) nem nome de função, variável ou " <>
           "arquivo do código; diga o que fazem (ex.: \"a leitura do plano\", \"a parte que cria " <>
           "o primeiro administrador\")."

  @doc "O texto da orientação."
  def texto, do: @texto

  @doc "A lista com a orientação no FIM, ou intacta para quem não é conversacional."
  def anexar(messages, agent) when is_list(messages) and is_binary(agent) do
    if agent in Engine.Agents.Conversacionais.prefixos(),
      do: messages ++ [%{"role" => "system", "content" => @texto}],
      else: messages
  end

  def anexar(messages, _agent), do: messages
end
