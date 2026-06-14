defmodule SymphonyElixir.GitHub.AdapterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.GitHub.Adapter

  defmodule FakeGitHubClient do
    @spec fetch_candidate_issues() :: {:ok, [:candidate]}
    def fetch_candidate_issues, do: {:ok, [:candidate]}

    @spec fetch_issues_by_states([String.t()]) :: {:ok, [String.t()]}
    def fetch_issues_by_states(states), do: {:ok, states}

    @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [String.t()]}
    def fetch_issue_states_by_ids(ids), do: {:ok, ids}

    @spec create_comment(String.t(), String.t()) :: :ok
    def create_comment(issue_id, body) do
      send(self(), {:comment, issue_id, body})
      :ok
    end

    @spec update_issue_state(String.t(), String.t()) :: :ok
    def update_issue_state(issue_id, state_name) do
      send(self(), {:state, issue_id, state_name})
      :ok
    end
  end

  test "delegates tracker callbacks to configured github client" do
    Application.put_env(:symphony_elixir, :github_client_module, FakeGitHubClient)

    assert {:ok, [:candidate]} = Adapter.fetch_candidate_issues()
    assert {:ok, ["Todo"]} = Adapter.fetch_issues_by_states(["Todo"])
    assert {:ok, ["I_1"]} = Adapter.fetch_issue_states_by_ids(["I_1"])
    assert :ok = Adapter.create_comment("I_1", "body")
    assert_receive {:comment, "I_1", "body"}
    assert :ok = Adapter.update_issue_state("PVTI_1", "Done")
    assert_receive {:state, "PVTI_1", "Done"}
  end
end
