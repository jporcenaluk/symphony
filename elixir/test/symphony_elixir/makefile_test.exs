defmodule SymphonyElixir.MakefileTest do
  use ExUnit.Case, async: true

  @makefile Path.expand("../../Makefile", __DIR__)
  @ack_flag "--i-understand-that-this-will-be-running-without-the-usual-guardrails"

  test "server target starts Symphony with overridable defaults" do
    makefile = File.read!(@makefile)

    assert makefile =~ "PORT ?= 4000"
    assert makefile =~ "WORKFLOW ?= ./WORKFLOW.md"
    assert makefile =~ "server"
    assert makefile =~ "start"
    assert makefile =~ @ack_flag
    assert makefile =~ "--port $(PORT)"
    assert makefile =~ "$(WORKFLOW)"
  end

  test "server target preflights the selected port" do
    makefile = File.read!(@makefile)

    assert makefile =~ "check-port"
    assert makefile =~ "Port $(PORT) is already in use"
    assert makefile =~ "make server PORT=<port>"
  end
end
