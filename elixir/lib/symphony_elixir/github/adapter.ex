defmodule SymphonyElixir.GitHub.Adapter do
  @moduledoc """
  GitHub-backed tracker adapter.
  """

  @behaviour SymphonyElixir.Tracker

  @impl true
  def fetch_candidate_issues, do: {:error, :github_adapter_not_implemented}

  @impl true
  def fetch_issues_by_states(_states), do: {:error, :github_adapter_not_implemented}

  @impl true
  def fetch_issue_states_by_ids(_issue_ids), do: {:error, :github_adapter_not_implemented}

  @impl true
  def create_comment(_issue_id, _body), do: {:error, :github_adapter_not_implemented}

  @impl true
  def update_issue_state(_issue_id, _state_name), do: {:error, :github_adapter_not_implemented}
end
