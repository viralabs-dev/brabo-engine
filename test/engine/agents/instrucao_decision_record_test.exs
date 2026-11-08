defmodule Engine.Agents.InstrucaoDecisionRecordTest do
  # AT-812: a instrução do `decision_record` é a MESMA nos 5 conversacionais
  # (atributo de módulo, sem acessor público): confere o texto no fonte.
  use ExUnit.Case, async: true

  @servidores ~w(po arquiteto dev_lead ux_designer staff)

  for s <- @servidores do
    test "#{s}_server pede afeta.modulos e a citação do módulo" do
      fonte = File.read!("lib/engine/agents/#{unquote(s)}_server.ex")
      assert fonte =~ ~S|`afeta: {modulos: [\"<módulo>\"]}` e cite |
      assert fonte =~ "`modules/<módulo>`."
    end
  end
end
