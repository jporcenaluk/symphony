defmodule SymphonyElixir.GitHub.ClientTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.GitHub.Client

  test "normalizes an eligible project issue item" do
    item =
      github_item(%{
        number: 12,
        title: "Add GitHub tracker",
        status: "Todo",
        priority: "High",
        blocked_by: []
      })

    assert issue = Client.normalize_project_item_for_test(item, tracker_settings())
    assert issue.id == "I_12"
    assert issue.tracker_item_id == "PVTI_12"
    assert issue.identifier == "jporcenaluk/symphony#12"
    assert issue.title == "Add GitHub tracker"
    assert issue.description == "Issue body"
    assert issue.state == "Todo"
    assert issue.priority == 4
    assert issue.url == "https://github.com/jporcenaluk/symphony/issues/12"
    assert issue.labels == ["symphony"]
    assert issue.assignee_id == "jporcenaluk"
    assert issue.blocked_by == []
  end

  test "ignores project items outside the configured repo and non-open issues" do
    assert is_nil(
             Client.normalize_project_item_for_test(
               github_item(%{repo_owner: "other", number: 3, status: "Todo"}),
               tracker_settings()
             )
           )

    assert is_nil(
             Client.normalize_project_item_for_test(
               github_item(%{issue_state: "CLOSED", number: 4, status: "Todo"}),
               tracker_settings()
             )
           )
  end

  test "normalizes native blockers" do
    item =
      github_item(%{
        number: 12,
        status: "Todo",
        blocked_by: [
          %{
            "id" => "I_block",
            "number" => 13,
            "state" => "OPEN",
            "title" => "Dependency",
            "repository" => %{"owner" => %{"login" => "jporcenaluk"}, "name" => "symphony"}
          }
        ]
      })

    assert issue = Client.normalize_project_item_for_test(item, tracker_settings())
    assert issue.blocked_by == [%{id: "I_block", identifier: "jporcenaluk/symphony#13", state: "OPEN"}]
  end

  test "filters active unblocked candidates and sorts by priority then age" do
    settings = tracker_settings()

    items = [
      github_item(%{number: 1, status: "Todo", priority: "Low", created_at: "2026-01-01T00:00:00Z"}),
      github_item(%{number: 2, status: "Todo", priority: "High", created_at: "2026-01-02T00:00:00Z"}),
      github_item(%{number: 3, status: "Todo", priority: "High", created_at: "2026-01-01T00:00:00Z"}),
      github_item(%{number: 4, status: "Backlog", priority: "P0", created_at: "2025-01-01T00:00:00Z"}),
      github_item(%{number: 5, status: "Human Review", priority: "P0", created_at: "2025-01-01T00:00:00Z"}),
      github_item(%{
        number: 6,
        status: "Todo",
        priority: "P0",
        blocked_by: [
          %{
            "id" => "I_block",
            "number" => 7,
            "state" => "OPEN",
            "title" => "Dependency",
            "repository" => %{"owner" => %{"login" => "jporcenaluk"}, "name" => "symphony"}
          }
        ]
      }),
      github_item(%{
        number: 8,
        status: "Todo",
        priority: "P0",
        blocked_by: [
          %{
            "id" => "I_closed",
            "number" => 9,
            "state" => "CLOSED",
            "title" => "Completed dependency",
            "repository" => %{"owner" => %{"login" => "jporcenaluk"}, "name" => "symphony"}
          }
        ],
        created_at: "2026-01-03T00:00:00Z"
      })
    ]

    assert {:ok, issues} = Client.normalize_candidate_items_for_test(items, settings)

    assert Enum.map(issues, & &1.identifier) == [
             "jporcenaluk/symphony#8",
             "jporcenaluk/symphony#3",
             "jporcenaluk/symphony#2",
             "jporcenaluk/symphony#1"
           ]
  end

  test "fetch_candidate_issues paginates project items through injected graphql client" do
    write_github_workflow!()

    pages = [
      {:ok,
       %{
         "data" => %{
           "user" => %{
             "projectV2" => %{
               "items" => %{
                 "nodes" => [github_item(%{number: 1})],
                 "pageInfo" => %{"hasNextPage" => true, "endCursor" => "cursor-1"}
               }
             }
           }
         }
       }},
      {:ok,
       %{
         "data" => %{
           "user" => %{
             "projectV2" => %{
               "items" => %{
                 "nodes" => [github_item(%{number: 2})],
                 "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
               }
             }
           }
         }
       }}
    ]

    Process.put(:github_graphql_pages, pages)

    graphql = fn query, variables ->
      [next | rest] = Process.get(:github_graphql_pages)
      Process.put(:github_graphql_pages, rest)
      send(self(), {:github_graphql, query, variables})
      next
    end

    assert {:ok, issues} = Client.fetch_candidate_issues_for_test(graphql)
    assert Enum.map(issues, & &1.identifier) == ["jporcenaluk/symphony#1", "jporcenaluk/symphony#2"]
    assert_receive {:github_graphql, query, %{owner: "jporcenaluk", number: 2, first: 50, blockerFirst: 50, after: nil}}
    assert query =~ "projectV2"
    assert_receive {:github_graphql, ^query, %{owner: "jporcenaluk", number: 2, first: 50, blockerFirst: 50, after: "cursor-1"}}
  end

  test "create_comment sends addComment mutation" do
    graphql = fn query, variables ->
      send(self(), {:github_graphql, query, variables})
      {:ok, %{"data" => %{"addComment" => %{"commentEdge" => %{"node" => %{"id" => "comment-1"}}}}}}
    end

    assert :ok = Client.create_comment_for_test("I_123", "progress", graphql)
    assert_receive {:github_graphql, query, %{subjectId: "I_123", body: "progress"}}
    assert query =~ "addComment"
  end

  test "update_issue_state resolves status option and updates project item field value" do
    write_github_workflow!()

    graphql = fn query, variables ->
      send(self(), {:github_graphql, query, variables})

      cond do
        query =~ "ProjectStatusMetadata" ->
          {:ok,
           %{
             "data" => %{
               "user" => %{
                 "projectV2" => %{
                   "id" => "PVT_1",
                   "fields" => %{
                     "nodes" => [
                       %{
                         "id" => "PVTSSF_status",
                         "name" => "Status",
                         "options" => [
                           %{"id" => "todo", "name" => "Todo"},
                           %{"id" => "done", "name" => "Done"}
                         ]
                       }
                     ]
                   }
                 }
               }
             }
           }}

        query =~ "updateProjectV2ItemFieldValue" ->
          {:ok, %{"data" => %{"updateProjectV2ItemFieldValue" => %{"projectV2Item" => %{"id" => "PVTI_1"}}}}}
      end
    end

    assert :ok = Client.update_issue_state_for_test("PVTI_1", "Done", graphql)
    assert_receive {:github_graphql, metadata_query, %{owner: "jporcenaluk", number: 2, fieldFirst: 50}}
    assert metadata_query =~ "ProjectStatusMetadata"

    assert_receive {:github_graphql, mutation,
                    %{projectId: "PVT_1", itemId: "PVTI_1", fieldId: "PVTSSF_status", optionId: "done"}}

    assert mutation =~ "updateProjectV2ItemFieldValue"
  end

  defp write_github_workflow! do
    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_kind: "github",
      tracker_owner: "jporcenaluk",
      tracker_project_number: 2,
      tracker_repo_owner: "jporcenaluk",
      tracker_repo_name: "symphony",
      tracker_active_states: ["Todo", "In Progress", "Merging", "Rework"]
    )
  end

  defp tracker_settings do
    %{
      repo_owner: "jporcenaluk",
      repo_name: "symphony",
      status_field: "Status",
      priority_field: "Priority",
      active_states: ["Todo", "In Progress", "Merging", "Rework"],
      priority_order: ["P0", "Urgent", "Critical", "P1", "High", "P2", "Medium", "P3", "Low"]
    }
  end

  defp github_item(overrides) do
    number = Map.get(overrides, :number, 12)
    repo_owner = Map.get(overrides, :repo_owner, "jporcenaluk")
    repo_name = Map.get(overrides, :repo_name, "symphony")

    %{
      "id" => "PVTI_#{number}",
      "fieldValues" => %{
        "nodes" => [
          %{"field" => %{"name" => "Status"}, "name" => Map.get(overrides, :status, "Todo")},
          %{"field" => %{"name" => "Priority"}, "name" => Map.get(overrides, :priority, "Medium")}
        ]
      },
      "content" => %{
        "__typename" => "Issue",
        "id" => "I_#{number}",
        "number" => number,
        "title" => Map.get(overrides, :title, "Issue title"),
        "body" => Map.get(overrides, :body, "Issue body"),
        "state" => Map.get(overrides, :issue_state, "OPEN"),
        "url" => "https://github.com/#{repo_owner}/#{repo_name}/issues/#{number}",
        "createdAt" => Map.get(overrides, :created_at, "2026-01-01T00:00:00Z"),
        "updatedAt" => Map.get(overrides, :updated_at, "2026-01-02T00:00:00Z"),
        "repository" => %{
          "owner" => %{"login" => repo_owner},
          "name" => repo_name
        },
        "labels" => %{"nodes" => [%{"name" => "symphony"}]},
        "assignees" => %{"nodes" => [%{"login" => "jporcenaluk"}]},
        "blockedBy" => %{"nodes" => Map.get(overrides, :blocked_by, [])}
      }
    }
  end
end
