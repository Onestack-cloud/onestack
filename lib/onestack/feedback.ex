defmodule Onestack.Feedback do
  import Ecto.Query
  alias Onestack.Repo
  alias Onestack.Feedback.{Feedback, Comment, Upvote}

  # Feedback functions
  def list_feedbacks(sort \\ :new, search_query \\ nil) do
    require Logger
    Logger.info("list_feedbacks called with sort: #{inspect(sort)}, search: #{inspect(search_query)}")

    query = from f in Feedback,
      left_join: u in assoc(f, :user),
      preload: [user: u]

    query = if search_query && search_query != "" do
      where(query, [f], fragment("? LIKE ? COLLATE NOCASE", f.title, ^"%#{search_query}%") or 
                         fragment("? LIKE ? COLLATE NOCASE", f.content, ^"%#{search_query}%"))
    else
      query
    end

    query =
      case sort do
        :new -> order_by(query, [f], desc: f.inserted_at)
        :old -> order_by(query, [f], asc: f.inserted_at)
        :most_votes -> order_by(query, [f], [desc: f.upvotes_count, desc: f.inserted_at])
        :least_votes -> order_by(query, [f], [asc: f.upvotes_count, desc: f.inserted_at])
        :top -> order_by(query, [f], [desc: f.upvotes_count, desc: f.inserted_at])
        _ -> order_by(query, [f], desc: f.inserted_at)
      end

    Logger.info("Generated query: #{inspect(query)}")
    result = Repo.all(query)
    Logger.info("Query returned #{length(result)} results")
    result
  end

  def get_feedback!(id) do
    Feedback
    |> Repo.get!(id)
    |> Repo.preload([:user, comments: [:user]])
  end

  def create_feedback(attrs \\ %{}) do
    %Feedback{}
    |> Feedback.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, feedback} ->
        feedback = Map.put(feedback, :has_upvoted, false)
        broadcast({:ok, feedback}, :feedback_created)
      error ->
        error
    end
  end

  def broadcast({:ok, feedback}, event) do
    Phoenix.PubSub.broadcast(Onestack.PubSub, "feedbacks", {event, feedback})
    {:ok, feedback}
  end

  def broadcast({:error, _} = error, _event), do: error

  def update_feedback(%Feedback{} = feedback, attrs) do
    feedback
    |> Feedback.changeset(attrs)
    |> Repo.update()
  end

  def delete_feedback(%Feedback{} = feedback) do
    Repo.delete(feedback)
  end

  def change_feedback(%Feedback{} = feedback, attrs \\ %{}) do
    Feedback.changeset(feedback, attrs)
  end

  def toggle_upvote(%Feedback{} = feedback, user) do
    if has_upvoted?(feedback, user.id) do
      remove_upvote(feedback, user.id)
    else
      add_upvote(feedback, user.id)
    end
  end

  def has_upvoted?(%Feedback{} = feedback, user_id) do
    Repo.exists?(from u in Upvote, where: u.feedback_id == ^feedback.id and u.user_id == ^user_id)
  end

  defp add_upvote(%Feedback{} = feedback, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:upvote, %Upvote{feedback_id: feedback.id, user_id: user_id})
    |> Ecto.Multi.update(:feedback, fn _ ->
      Feedback.changeset(feedback, %{upvotes_count: feedback.upvotes_count + 1})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{feedback: feedback}} -> {:ok, feedback}
      {:error, :upvote, changeset, _} -> {:error, changeset}
    end
  end

  defp remove_upvote(%Feedback{} = feedback, user_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete_all(:delete_upvote, from(u in Upvote, where: u.feedback_id == ^feedback.id and u.user_id == ^user_id))
    |> Ecto.Multi.update(:feedback, fn _ ->
      Feedback.changeset(feedback, %{upvotes_count: max(feedback.upvotes_count - 1, 0)})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{feedback: feedback}} -> {:ok, feedback}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  # Comment functions
  def list_comments(feedback_id) do
    Comment
    |> where([c], c.feedback_id == ^feedback_id)
    |> order_by([c], [desc: c.inserted_at])
    |> preload(:user)
    |> Repo.all()
  end

  def create_comment(attrs \\ %{}) do
    %Comment{}
    |> Comment.changeset(attrs)
    |> Repo.insert()
  end

  def delete_comment(%Comment{} = comment) do
    Repo.delete(comment)
  end

  def change_comment(%Comment{} = comment, attrs \\ %{}) do
    Comment.changeset(comment, attrs)
  end

  defp sort_feedbacks(query, :new) do
    order_by(query, [f], [desc: f.inserted_at])
  end

  defp sort_feedbacks(query, :top) do
    order_by(query, [f], [desc: f.upvotes_count, desc: f.inserted_at])
  end
end
