defmodule Engine.Harness.Tools.ConsultarImpactoDoModulo do
  @moduledoc """
  Ferramenta de LEITURA do dev agent (RN-1167, AT-924): pelo grafo, quem
  depende de um módulo, o que ele expõe, que decisões o citam e a versão do
  contrato.

  `:direct` — LER não é efeito externo. CONTIDA (ADR 0060): o projeto vem do
  contexto do laço (`ctx.project_id`), nunca de parâmetro; o único parâmetro é
  o nome do módulo; e cada lista tem teto, com o total real dito quando corta.
  Grafo desligado (503) é erro nomeado, NUNCA lista vazia.
  """

  @behaviour Engine.Harness.Tool

  alias Engine.Sessions.EngineApiClient

  @max_itens 40

  @impl true
  def spec do
    %{
      name: "consultar_impacto_do_modulo",
      description: """
      Consulta o grafo do projeto para um módulo: quais módulos dependem dele,
      o que ele expõe, que decisões o citam e a versão do contrato. Use antes de
      mudar o que um módulo expõe, para saber quem seria afetado. Recebe só o
      nome do módulo, como no cartão. Se o grafo estiver desligado, a resposta
      diz isso; nesse caso use `listar_contratos_de_modulos`.
      """,
      parameters: %{
        "type" => "object",
        "properties" => %{"modulo" => %{"type" => "string", "description" => "Nome do módulo."}},
        "required" => ["modulo"]
      }
    }
  end

  @impl true
  def category, do: :direct

  @impl true
  def run(%{"modulo" => modulo}, ctx) when is_binary(modulo) and modulo != "" do
    case EngineApiClient.consultar_impacto_do_modulo(ctx.project_id, modulo) do
      {:ok, %{"modulo" => _} = corpo} ->
        {:ok, renderizar(corpo)}

      {:ok, outro} ->
        {:error, "resposta inesperada da consulta de impacto: #{inspect(outro)}"}

      {:error, {404, _}} ->
        {:ok,
         "O módulo \"#{modulo}\" não tem nó no grafo (ainda não projetado ou nome diferente)."}

      {:error, {503, _}} ->
        {:error, "grafo desligado ou fora do ar: sem resposta de impacto (não é lista vazia)."}

      {:error, reason} ->
        {:error, "falha ao consultar o impacto do módulo: #{inspect(reason)}"}
    end
  end

  def run(args, _ctx),
    do:
      {:error,
       "consultar_impacto_do_modulo exige `modulo`; chaves recebidas: #{inspect(Map.keys(args))}"}

  defp renderizar(c) do
    expoe = Enum.map(Map.get(c, "expoe", []), &"[#{&1["tipo"]}] #{&1["assinatura"]}")
    decisoes = Enum.map(Map.get(c, "decisoes", []), &"#{&1["id"]} — #{&1["titulo"]}")

    Enum.join(
      [
        "Impacto de \"#{c["modulo"]}\" (contrato versão #{c["contratoVersao"] || "sem versão"}).",
        "Dependem dele: #{lista(Map.get(c, "dependentes", []))}.",
        "Ele depende de: #{lista(Map.get(c, "dependeDe", []))}.",
        "Expõe: #{lista(expoe)}.",
        "Decisões que o citam: #{lista(decisoes)}."
      ],
      "\n"
    )
  end

  defp lista([]), do: "nenhum"

  defp lista(itens) do
    texto = itens |> Enum.take(@max_itens) |> Enum.join("; ")

    case length(itens) - @max_itens do
      n when n > 0 ->
        "#{texto} (+ #{n} não mostrado(s) pelo teto de #{@max_itens}; total #{length(itens)})"

      _ ->
        texto
    end
  end
end
