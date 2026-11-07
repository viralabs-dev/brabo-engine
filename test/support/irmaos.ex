defmodule Engine.Irmaos do
  @moduledoc """
  Caminho de um arquivo de um repo IRMÃO (`brabo-api`, `brabo-runner`) para os
  testes que conferem um espelho entre repos. `BRABO_<REPO>_DIR` manda; senão
  vale o clone ao lado deste (`../brabo-<repo>`, o layout do `clonar-tudo.sh`).
  O CI faz o checkout dos irmãos e exporta as variáveis (AT-776).
  """

  def caminho(repo, relativo) when repo in ["api", "runner"] do
    base =
      System.get_env("BRABO_#{String.upcase(repo)}_DIR") ||
        Path.expand("../brabo-#{repo}", File.cwd!())

    Path.join(base, relativo)
  end
end
