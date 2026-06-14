defmodule SymphonyElixir.GitHub.Cli do
  @moduledoc """
  Runs GitHub GraphQL requests through the authenticated local `gh` CLI.
  """

  @type runner :: (String.t(), [String.t()], keyword() -> {String.t(), non_neg_integer()})

  @spec graphql(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def graphql(query, variables \\ %{}, opts \\ [])
      when is_binary(query) and is_map(variables) and is_list(opts) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)

    case runner.("gh", graphql_args(query, variables), stderr_to_stdout: true) do
      {output, 0} -> decode_output(output)
      {output, _exit_code} -> {:error, classify_error(output)}
    end
  rescue
    error in ErlangError ->
      case error.original do
        :enoent -> {:error, :missing_github_cli}
        reason -> {:error, {:github_cli_error, reason}}
      end
  end

  defp graphql_args(query, variables) do
    ["api", "graphql", "-f", "query=#{query}"] ++ variable_args(variables)
  end

  defp variable_args(variables) when is_map(variables) do
    variables
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.flat_map(fn {key, value} -> ["-F", "#{key}=#{value}"] end)
  end

  defp decode_output(output) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, {:invalid_github_cli_json, reason}}
    end
  end

  defp classify_error(output) when is_binary(output) do
    normalized = String.downcase(output)

    cond do
      String.contains?(normalized, "not logged into") or
          (String.contains?(normalized, "token in") and String.contains?(normalized, "invalid")) ->
        :github_cli_not_authenticated

      String.contains?(normalized, "required scopes") and String.contains?(normalized, "project") ->
        :missing_github_project_scope

      String.contains?(normalized, "could not resolve to a projectv2") ->
        :github_project_not_found

      true ->
        {:github_cli_failed, String.trim(output)}
    end
  end
end
