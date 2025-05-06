defmodule Onestack.Feedback.Upvote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "feedback_upvotes" do
    belongs_to :user, Onestack.Accounts.User
    belongs_to :feedback, Onestack.Feedback.Feedback

    timestamps()
  end

  def changeset(upvote, attrs) do
    upvote
    |> cast(attrs, [:user_id, :feedback_id])
    |> validate_required([:user_id, :feedback_id])
    |> unique_constraint([:user_id, :feedback_id], name: :feedback_upvotes_user_id_feedback_id_index)
  end
end
