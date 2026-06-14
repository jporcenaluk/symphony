defmodule SymphonyElixir.GitHub.CliTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.GitHub.Cli

  test "graphql sends query and variables through gh api graphql" do
    runner = fn "gh", args, opts ->
      send(self(), {:gh_called, args, opts})
      {Jason.encode!(%{"data" => %{"viewer" => %{"login" => "jporcenaluk"}}}), 0}
    end

    assert {:ok, %{"data" => %{"viewer" => %{"login" => "jporcenaluk"}}}} =
             Cli.graphql("query Viewer($first: Int!) { viewer { login } }", %{"first" => 10, "after" => nil}, runner: runner)

    assert_receive {:gh_called, ["api", "graphql", "-f", query_arg, "-F", first_arg], opts}
    assert query_arg == "query=query Viewer($first: Int!) { viewer { login } }"
    assert first_arg == "first=10"
    assert opts == [stderr_to_stdout: true]
  end

  test "graphql normalizes missing gh executable" do
    runner = fn "gh", _args, _opts -> raise ErlangError, original: :enoent end

    assert {:error, :missing_github_cli} =
             Cli.graphql("query Viewer { viewer { login } }", %{}, runner: runner)
  end

  test "graphql normalizes authentication and project scope errors" do
    auth_runner = fn "gh", _args, _opts ->
      {"the token in hosts.yml is invalid", 1}
    end

    assert {:error, :github_cli_not_authenticated} =
             Cli.graphql("query Viewer { viewer { login } }", %{}, runner: auth_runner)

    scope_runner = fn "gh", _args, _opts ->
      {"Your token has not been granted the required scopes: project", 1}
    end

    assert {:error, :missing_github_project_scope} =
             Cli.graphql("query Viewer { viewer { login } }", %{}, runner: scope_runner)
  end

  test "graphql rejects invalid JSON output" do
    runner = fn "gh", _args, _opts -> {"not json", 0} end

    assert {:error, {:invalid_github_cli_json, _reason}} =
             Cli.graphql("query Viewer { viewer { login } }", %{}, runner: runner)
  end
end
