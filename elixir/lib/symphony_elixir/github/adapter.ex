defmodule SymphonyElixir.GitHub.Adapter do
  @moduledoc """
  GitHub-backed tracker adapter.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.GitHub.Client

  @impl true
  def fetch_candidate_issues, do: client_module().fetch_candidate_issues()

  @impl true
  def fetch_issues_by_states(states), do: client_module().fetch_issues_by_states(states)

  @impl true
  def fetch_issue_states_by_ids(issue_ids), do: client_module().fetch_issue_states_by_ids(issue_ids)

  @impl true
  def create_comment(issue_id, body), do: client_module().create_comment(issue_id, body)

  @impl true
  def update_issue_state(issue_id, state_name), do: client_module().update_issue_state(issue_id, state_name)

  defp client_module do
    Application.get_env(:symphony_elixir, :github_client_module, Client)
  end
end
