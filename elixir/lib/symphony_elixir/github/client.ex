defmodule SymphonyElixir.GitHub.Client do
  @moduledoc """
  GitHub Projects v2 GraphQL client and response normalizer.
  """

  alias SymphonyElixir.{Config, GitHub.Cli, Tracker.Issue}

  @item_page_size 50
  @blocker_page_size 50
  @field_page_size 50

  @project_items_query """
  query SymphonyGitHubProjectItems($owner: String!, $number: Int!, $first: Int!, $blockerFirst: Int!, $after: String) {
    user(login: $owner) {
      projectV2(number: $number) {
        items(first: $first, after: $after) {
          nodes {
            id
            fieldValues(first: 20) {
              nodes {
                ... on ProjectV2ItemFieldSingleSelectValue {
                  name
                  field {
                    ... on ProjectV2SingleSelectField {
                      name
                    }
                  }
                }
              }
            }
            content {
              ... on Issue {
                __typename
                id
                number
                title
                body
                state
                url
                createdAt
                updatedAt
                repository {
                  owner {
                    login
                  }
                  name
                }
                labels(first: 50) {
                  nodes {
                    name
                  }
                }
                assignees(first: 10) {
                  nodes {
                    login
                  }
                }
                blockedBy(first: $blockerFirst) {
                  nodes {
                    id
                    number
                    state
                    title
                    repository {
                      owner {
                        login
                      }
                      name
                    }
                  }
                }
              }
            }
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    }
  }
  """

  @add_comment_mutation """
  mutation SymphonyGitHubAddComment($subjectId: ID!, $body: String!) {
    addComment(input: {subjectId: $subjectId, body: $body}) {
      commentEdge {
        node {
          id
        }
      }
    }
  }
  """

  @project_status_metadata_query """
  query ProjectStatusMetadata($owner: String!, $number: Int!, $fieldFirst: Int!) {
    user(login: $owner) {
      projectV2(number: $number) {
        id
        fields(first: $fieldFirst) {
          nodes {
            ... on ProjectV2SingleSelectField {
              id
              name
              options {
                id
                name
              }
            }
          }
        }
      }
    }
  }
  """

  @update_status_mutation """
  mutation SymphonyGitHubUpdateProjectStatus($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
    updateProjectV2ItemFieldValue(
      input: {
        projectId: $projectId,
        itemId: $itemId,
        fieldId: $fieldId,
        value: {singleSelectOptionId: $optionId}
      }
    ) {
      projectV2Item {
        id
      }
    }
  }
  """

  @spec fetch_candidate_issues() :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues do
    tracker = Config.settings!().tracker

    with {:ok, items} <- fetch_project_items(tracker, &Cli.graphql/2) do
      {:ok, normalize_candidate_items(items, tracker)}
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issues_by_states(states) when is_list(states) do
    tracker = Config.settings!().tracker |> Map.put(:active_states, Enum.map(states, &to_string/1))

    with {:ok, items} <- fetch_project_items(tracker, &Cli.graphql/2) do
      {:ok, normalize_candidate_items(items, tracker)}
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Issue.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids = MapSet.new(issue_ids)
    tracker = Config.settings!().tracker

    with {:ok, items} <- fetch_project_items(tracker, &Cli.graphql/2) do
      issues =
        items
        |> Enum.map(&normalize_project_item(&1, tracker))
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(&MapSet.member?(ids, &1.id))

      {:ok, issues}
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body), do: create_comment(issue_id, body, &Cli.graphql/2)

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(item_id, state_name), do: update_issue_state(item_id, state_name, &Cli.graphql/2)

  @doc false
  @spec normalize_project_item_for_test(map(), map()) :: Issue.t() | nil
  def normalize_project_item_for_test(item, tracker), do: normalize_project_item(item, tracker)

  @doc false
  @spec normalize_candidate_items_for_test([map()], map()) :: {:ok, [Issue.t()]}
  def normalize_candidate_items_for_test(items, tracker), do: {:ok, normalize_candidate_items(items, tracker)}

  @doc false
  @spec fetch_candidate_issues_for_test((String.t(), map() -> {:ok, map()} | {:error, term()})) ::
          {:ok, [Issue.t()]} | {:error, term()}
  def fetch_candidate_issues_for_test(graphql) when is_function(graphql, 2) do
    tracker = Config.settings!().tracker

    with {:ok, items} <- fetch_project_items(tracker, graphql) do
      {:ok, normalize_candidate_items(items, tracker)}
    end
  end

  @doc false
  @spec create_comment_for_test(String.t(), String.t(), (String.t(), map() -> {:ok, map()} | {:error, term()})) ::
          :ok | {:error, term()}
  def create_comment_for_test(issue_id, body, graphql), do: create_comment(issue_id, body, graphql)

  @doc false
  @spec update_issue_state_for_test(String.t(), String.t(), (String.t(), map() -> {:ok, map()} | {:error, term()})) ::
          :ok | {:error, term()}
  def update_issue_state_for_test(item_id, state_name, graphql), do: update_issue_state(item_id, state_name, graphql)

  defp fetch_project_items(tracker, graphql) do
    fetch_project_items_page(tracker, graphql, nil, [])
  end

  defp fetch_project_items_page(tracker, graphql, after_cursor, acc_items) do
    variables = %{
      owner: tracker_value(tracker, :owner),
      number: tracker_value(tracker, :project_number),
      first: @item_page_size,
      blockerFirst: @blocker_page_size,
      after: after_cursor
    }

    with {:ok, response} <- graphql.(@project_items_query, variables),
         {:ok, items, page_info} <- decode_project_items_response(response) do
      updated_items = Enum.reverse(items, acc_items)

      if page_info["hasNextPage"] do
        fetch_project_items_page(tracker, graphql, page_info["endCursor"], updated_items)
      else
        {:ok, Enum.reverse(updated_items)}
      end
    end
  end

  defp decode_project_items_response(response) do
    case get_in(response, ["data", "user", "projectV2", "items"]) do
      %{"nodes" => nodes, "pageInfo" => page_info} when is_list(nodes) and is_map(page_info) ->
        {:ok, nodes, page_info}

      _ ->
        {:error, :github_project_not_found}
    end
  end

  defp normalize_candidate_items(items, tracker) do
    items
    |> Enum.map(&normalize_project_item(&1, tracker))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(&1.state in tracker_value(tracker, :active_states, [])))
    |> Enum.reject(&blocked_by_open_issue?/1)
    |> Enum.sort_by(&dispatch_sort_key(&1, tracker))
  end

  defp normalize_project_item(%{"content" => %{"__typename" => "Issue"} = issue} = item, tracker) do
    with true <- configured_repo?(issue, tracker),
         "OPEN" <- Map.get(issue, "state"),
         status when is_binary(status) <- field_value(item, tracker_value(tracker, :status_field, "Status")) do
      repo_owner = get_in(issue, ["repository", "owner", "login"])
      repo_name = get_in(issue, ["repository", "name"])
      number = Map.get(issue, "number")

      %Issue{
        id: Map.get(issue, "id"),
        identifier: "#{repo_owner}/#{repo_name}##{number}",
        title: Map.get(issue, "title"),
        description: Map.get(issue, "body"),
        priority: priority_rank(field_value(item, tracker_value(tracker, :priority_field, "Priority")), tracker),
        state: status,
        branch_name: nil,
        url: Map.get(issue, "url"),
        assignee_id: get_in(issue, ["assignees", "nodes", Access.at(0), "login"]),
        tracker_item_id: Map.get(item, "id"),
        blocked_by: normalize_open_blockers(issue, repo_owner, repo_name),
        labels: normalize_labels(issue),
        assigned_to_worker: true,
        created_at: parse_datetime(Map.get(issue, "createdAt")),
        updated_at: parse_datetime(Map.get(issue, "updatedAt"))
      }
    else
      _ -> nil
    end
  end

  defp normalize_project_item(_item, _tracker), do: nil

  defp configured_repo?(issue, tracker) do
    get_in(issue, ["repository", "owner", "login"]) == tracker_value(tracker, :repo_owner) and
      get_in(issue, ["repository", "name"]) == tracker_value(tracker, :repo_name)
  end

  defp field_value(item, field_name) do
    item
    |> get_in(["fieldValues", "nodes"])
    |> List.wrap()
    |> Enum.find_value(fn
      %{"field" => %{"name" => ^field_name}, "name" => value} -> value
      _ -> nil
    end)
  end

  defp priority_rank(nil, tracker), do: length(tracker_value(tracker, :priority_order, []))

  defp priority_rank(priority, tracker) when is_binary(priority) do
    priority_order = tracker_value(tracker, :priority_order, [])

    case Enum.find_index(priority_order, &(&1 == priority)) do
      nil -> length(priority_order)
      index -> index
    end
  end

  defp normalize_open_blockers(issue, fallback_owner, fallback_name) do
    issue
    |> get_in(["blockedBy", "nodes"])
    |> List.wrap()
    |> Enum.filter(&(Map.get(&1, "state") == "OPEN"))
    |> Enum.map(fn blocker ->
      repo_owner = get_in(blocker, ["repository", "owner", "login"]) || fallback_owner
      repo_name = get_in(blocker, ["repository", "name"]) || fallback_name

      %{
        id: Map.get(blocker, "id"),
        identifier: "#{repo_owner}/#{repo_name}##{Map.get(blocker, "number")}",
        state: Map.get(blocker, "state")
      }
    end)
  end

  defp normalize_labels(issue) do
    issue
    |> get_in(["labels", "nodes"])
    |> List.wrap()
    |> Enum.map(&Map.get(&1, "name"))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&(String.trim(&1) |> String.downcase()))
  end

  defp blocked_by_open_issue?(%Issue{blocked_by: blockers}) do
    Enum.any?(blockers, &(&1.state == "OPEN"))
  end

  defp dispatch_sort_key(issue, tracker) do
    {issue.priority || length(tracker_value(tracker, :priority_order, [])),
     issue.created_at || ~U[9999-12-31 00:00:00Z]}
  end

  defp create_comment(issue_id, body, graphql) do
    with {:ok, response} <- graphql.(@add_comment_mutation, %{subjectId: issue_id, body: body}),
         comment_id when is_binary(comment_id) <-
           get_in(response, ["data", "addComment", "commentEdge", "node", "id"]) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :github_comment_create_failed}
    end
  end

  defp update_issue_state(item_id, state_name, graphql) do
    tracker = Config.settings!().tracker

    with {:ok, project_id, field_id, option_id} <- resolve_status_option(tracker, state_name, graphql),
         {:ok, response} <-
           graphql.(@update_status_mutation, %{
             projectId: project_id,
             itemId: item_id,
             fieldId: field_id,
             optionId: option_id
           }),
         updated_id when is_binary(updated_id) <-
           get_in(response, ["data", "updateProjectV2ItemFieldValue", "projectV2Item", "id"]) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :github_status_update_failed}
    end
  end

  defp resolve_status_option(tracker, state_name, graphql) do
    variables = %{
      owner: tracker_value(tracker, :owner),
      number: tracker_value(tracker, :project_number),
      fieldFirst: @field_page_size
    }

    with {:ok, response} <- graphql.(@project_status_metadata_query, variables),
         %{"id" => project_id, "fields" => %{"nodes" => fields}} <-
           get_in(response, ["data", "user", "projectV2"]),
         %{"id" => field_id, "options" => options} <-
           Enum.find(fields, &(Map.get(&1, "name") == tracker_value(tracker, :status_field, "Status"))),
         %{"id" => option_id} <- Enum.find(options, &(Map.get(&1, "name") == state_name)) do
      {:ok, project_id, field_id, option_id}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :github_status_option_not_found}
    end
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp tracker_value(tracker, key, default \\ nil) do
    Map.get(tracker, key, Map.get(tracker, to_string(key), default))
  end
end
