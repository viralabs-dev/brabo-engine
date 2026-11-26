defmodule Engine.Harness.FraseParaLeigo do
  @moduledoc """
  A regra de linguagem para quem não programa (AT-1021, RN-1529; AT-1026,
  RN-1533), numa casa só: os padrões que o texto mostrado à pessoa não pode ter.
  Espelha `brabo-api:src/domain/linguagem/frase-para-leigo.ts` — mudou lá,
  muda aqui.

  Dois níveis:
  - `frase_para_leigo/2` e `sem_jargao/1`: a regra INTEIRA (frase curta, sem
    arquivo, caminho, identificador, código de erro) — `report_blocked`,
    `declare_open_question` com opções e `emit_qa_verdict`;
  - `sem_identificador/1`: só o identificador interno e o número de máquina
    (UUID, hash, "similaridade 0.817") — texto livre, como a pergunta do
    `ask_structured_questions`, onde nome de arquivo ou `snake_case` podem ser
    o assunto.
  """

  @id_interno [
    {"UUID", ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i},
    {"hash hexadecimal", ~r/\b[0-9a-f]{12,}\b/i}
  ]

  @numero_de_maquina [
    {"número de similaridade ou limiar",
     ~r/\b(similaridade|limiar|similarity|threshold)\b\D{0,15}\d/iu},
    {"número decimal cru", ~r/(?<![\d.,])0[.,]\d{3}(?!\d)/}
  ]

  @proibidos @id_interno ++
               [
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
                 {"código HTTP", ~r/\berro\s+[1-5]\d{2}\b/i}
               ]

  @doc "`:ok` ou `{:error, motivo}` da regra inteira, com teto e \"uma frase\"."
  def frase_para_leigo(texto, max \\ 160)

  def frase_para_leigo(texto, max) when is_binary(texto) do
    t = String.trim(texto)

    cond do
      t == "" -> {:error, "vazio"}
      String.length(t) > max -> {:error, "passa de #{max} caracteres"}
      String.contains?(t, ". ") or String.contains?(t, "\n") -> {:error, "mais de uma frase"}
      true -> achar(t, @proibidos)
    end
  end

  def frase_para_leigo(_, _), do: {:error, "precisa ser texto"}

  @doc "Só os padrões da regra (sem teto nem 'uma frase'): `:ok` ou `{:error, motivo}`."
  def sem_jargao(texto) when is_binary(texto), do: achar(texto, @proibidos)

  @doc "Só identificador interno e número de máquina: `:ok` ou `{:error, motivo}`."
  def sem_identificador(texto) when is_binary(texto),
    do: achar(texto, @id_interno ++ @numero_de_maquina)

  defp achar(t, padroes) do
    case Enum.find(padroes, fn {_, re} -> Regex.match?(re, t) end) do
      nil -> :ok
      {motivo, _} -> {:error, "tem #{motivo}"}
    end
  end
end
