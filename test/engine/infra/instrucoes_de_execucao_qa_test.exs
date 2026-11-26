defmodule Engine.Infra.InstrucoesDeExecucaoQaTest do
  use ExUnit.Case, async: true

  alias Engine.Infra.InstrucoesDeExecucao

  @digest String.duplicate("a", 64)
  @base %{
    "command" => "docker compose up --build",
    "urls" => [
      %{"label" => "Swagger", "url" => "http://localhost:8080/docs", "kind" => "api_docs"}
    ],
    "envExample" => true
  }

  defp com_qa(qa), do: Map.put(@base, "qa", qa)
  defp servico, do: %{"name" => "db", "image" => "postgres@sha256:" <> @digest}

  test "run.qa válido passa e é preservado; null equivale a ausente" do
    qa = %{"services" => [Map.put(servico(), "env", %{"POSTGRES_PASSWORD" => "x"})]}
    assert {:ok, %{"qa" => ^qa}} = InstrucoesDeExecucao.validar(com_qa(qa))
    assert {:ok, run} = InstrucoesDeExecucao.validar(com_qa(nil))
    refute Map.has_key?(run, "qa")
  end

  test "run sem qa não ganha a chave (não-regressão)" do
    assert {:ok, run} = InstrucoesDeExecucao.validar(@base)
    refute Map.has_key?(run, "qa")
  end

  test "RN-1507: tag explícita passa (a api fixa o digest); latest e imagem sem tag são recusadas" do
    com_tag = %{servico() | "image" => "postgres:16"}
    assert {:ok, _} = InstrucoesDeExecucao.validar(com_qa(%{"services" => [com_tag]}))

    for ruim <- ["postgres:latest", "postgres", "localhost:5000/postgres"] do
      sem_versao = %{servico() | "image" => ruim}
      assert {:error, m} = InstrucoesDeExecucao.validar(com_qa(%{"services" => [sem_versao]}))
      assert m =~ "versão fixa"
    end
  end

  test "recusa nome repetido, env inválido e mais de 6 serviços" do
    assert {:error, m} =
             InstrucoesDeExecucao.validar(com_qa(%{"services" => [servico(), servico()]}))

    assert m =~ "repetido"

    ruim = Map.put(servico(), "env", %{"minusculo" => "x"})
    assert {:error, _} = InstrucoesDeExecucao.validar(com_qa(%{"services" => [ruim]}))

    sete = for i <- 1..7, do: %{servico() | "name" => "s#{i}"}
    assert {:error, _} = InstrucoesDeExecucao.validar(com_qa(%{"services" => sete}))
  end
end
