defmodule Onestack.Feedback.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "feedback_comments" do
    field :content, :string
    belongs_to :user, Onestack.Accounts.User
    belongs_to :feedback, Onestack.Feedback.Feedback

    timestamps()
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:content, :user_id, :feedback_id])
    |> validate_required([:content, :user_id, :feedback_id])
  end
end
