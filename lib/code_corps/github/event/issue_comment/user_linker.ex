defmodule CodeCorps.GitHub.Event.IssueComment.UserLinker do
  @moduledoc ~S"""
  In charge of finding a user to link with a Comment when processing an
  IssueComment webhook.
  """

  import Ecto.Query

  alias CodeCorps.{
    Accounts,
    Comment,
    Repo,
    User
  }

  @typep linking_result :: {:ok, User.t} |
                           {:error, :multiple_users} |
                           {:error, :user_not_found}

  @doc ~S"""
  Finds or creates a User using information contained in an IssueComment webhook
  payload.

  The process is as follows

  Find all affected Comment records and take their user associations

  If there are no results and the user type in the payload is a bot, this
  means the webhook was somehow received for a comment being created from
  CodeCorps by an unconnected user before the record was actually inserted into
  the database.

  This is an unexpected scenario and the processing should error out.

  If there are no results and the user type in the payload is not a bot, this
  means the comment was created on Github directly, so a temporary user is
  created.

  If there are multiple results, this is, again, an unexpected scenario and
  should error out.
  """
  @spec find_or_create_user(map) :: {:ok, User.t}
  def find_or_create_user(%{"comment" => %{"user" => user_attrs}} = attrs) do
    attrs
    |> match_users
    |> marshall_response(user_attrs)
  end

  @spec match_users(map) :: list(User.t)
  defp match_users(%{"comment" => %{"id" => github_id}}) do
    query = from u in User,
      distinct: u.id,
      join: c in Comment, on: u.id == c.user_id, where: c.github_id == ^github_id

    query |> Repo.all
  end

  @spec marshall_response(list, map) :: linking_result
  defp marshall_response([%User{} = single_user], %{}), do: {:ok, single_user}
  defp marshall_response([], %{"type" => "User"} = user_attrs) do
    user_attrs |> find_or_create_disassociated_user()
  end
  defp marshall_response([], %{}), do: {:error, :user_not_found}
  defp marshall_response([_head | _tail], %{}), do: {:error, :multiple_users}

  @spec find_or_create_disassociated_user(map) :: {:ok, User.t}
  def find_or_create_disassociated_user(%{"id" => github_id} = attrs) do
    case User |> Repo.get_by(github_id: github_id) do
      nil -> attrs |> Accounts.create_from_github
      %User{} = user -> {:ok, user}
    end
  end
end
