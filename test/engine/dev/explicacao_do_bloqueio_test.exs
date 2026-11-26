defmodule Engine.Dev.ExplicacaoDoBloqueioTest do
  @moduledoc """
  AT-1021 (RN-1529/RN-1530): a regra de linguagem para leigo, o catálogo e a
  ferramenta `report_blocked`. Os negativos são frases reais da 30ª rodada do TP-01.
  """
  use ExUnit.Case, async: true

  alias Engine.Dev.ExplicacaoDoBloqueio, as: E
  alias Engine.Dev.Tools.ReportBlocked

  @negativos [
    "package-lock.json da raiz alterado pelo npm install",
    "ECONNREFUSED 127.0.0.1:5432",
    "desfechos (commit, push): [:refused, :executed]",
    "app_saiu (código 1) Missing script: build",
    "A Infra não declarou run.qa.services no projeto",
    "A imagem sha256 " <> String.duplicate("ab12", 16) <> " não foi achada",
    "Falha em `npm run build`",
    "Erro em src/app/main",
    "O provedor devolveu 429",
    "Duas frases. Aqui está a segunda"
  ]

  @positivos [
    "Não deu para subir o ambiente de teste.",
    "O agente parou sem concluir e sem dizer o motivo",
    "Concluir sem subir o app",
    "O banco de teste só existe no compose do projeto"
  ]

  test "a regra de linguagem recusa os negativos reais e aceita os positivos" do
    for n <- @negativos, do: assert({:error, _} = E.frase_para_leigo(n), n)
    for p <- @positivos, do: assert(:ok = E.frase_para_leigo(p), p)
    assert {:error, _} = E.frase_para_leigo(String.duplicate("a ", 90))
    assert {:error, _} = E.frase_para_leigo("Concluir sem subir o aplicativo agora mesmo ok", 40)
  end

  test "todo código do catálogo tem causa e rótulos na regra, e 1 a 2 ações" do
    assert length(E.codigos()) >= 25

    for c <- E.codigos() do
      e = E.de(c)
      assert e.codigo == Atom.to_string(c)
      assert :ok = E.frase_para_leigo(e.causa), "causa de #{c}"
      assert length(e.acoes) in 1..2, "ações de #{c}"

      for a <- e.acoes do
        assert :ok = E.frase_para_leigo(a.rotulo, 40), "rótulo de #{c}"
        assert is_binary(a.orientacao)
      end
    end
  end

  test "os códigos citados pelo levantamento existem" do
    for c <-
          ~w(qa_instancia_indisponivel commit_recusado limite_de_iteracoes limite_de_iteracoes_correcao
             orcamento_excedido credito_do_provedor falha_de_rede parada_sem_sinal generico)a,
        do: assert(c in E.codigos())
  end

  @acoes [
    %{
      "rotulo" => "Concluir sem subir o app",
      "orientacao" => "Conclua sem a prova do app; registre o motivo."
    }
  ]

  describe "report_blocked" do
    @base %{"reason" => "r", "diagnosis" => "d"}

    test "sem causa_para_leigo ou sem acoes devolve erro ao modelo" do
      assert {:error, _} = ReportBlocked.run(Map.put(@base, "acoes", @acoes), %{})

      assert {:error, _} =
               ReportBlocked.run(Map.put(@base, "causa_para_leigo", "Falta o app."), %{})
    end

    test "causa fora da regra, rótulo fora da regra e mais de 2 ações voltam ao modelo" do
      ruim = Map.merge(@base, %{"causa_para_leigo" => "Falta o package.json", "acoes" => @acoes})
      assert {:error, msg} = ReportBlocked.run(ruim, %{})
      assert msg =~ "causa_para_leigo"

      rotulo = [%{"rotulo" => "Rodar `npm test`", "orientacao" => "x"}]
      ruim = Map.merge(@base, %{"causa_para_leigo" => "Falta o app.", "acoes" => rotulo})
      assert {:error, _} = ReportBlocked.run(ruim, %{})

      tres = List.duplicate(hd(@acoes), 3)
      ruim = Map.merge(@base, %{"causa_para_leigo" => "Falta o app.", "acoes" => tres})
      assert {:error, _} = ReportBlocked.run(ruim, %{})
    end

    test "com os campos é aceito, e o hook leva a explicação ao servidor" do
      args = Map.merge(@base, %{"causa_para_leigo" => "Falta o app.", "acoes" => @acoes})
      assert {:ok, _} = ReportBlocked.run(args, %{})

      assert {:halt, {"report_blocked", %{explicacao: %{causa: "Falta o app.", acoes: [a]}}}} =
               Engine.Dev.Hooks.Termination.call(%{
                 tool: "report_blocked",
                 result_ok?: true,
                 args: args
               })

      assert a == %{
               rotulo: "Concluir sem subir o app",
               orientacao: "Conclua sem a prova do app; registre o motivo."
             }
    end
  end
end
