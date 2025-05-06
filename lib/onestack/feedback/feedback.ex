defmodule Onestack.Feedback.Feedback do
  use Ecto.Schema
  import Ecto.Changeset

  schema "feedbacks" do
    field :title, :string
    field :content, :string
    field :status, :string, default: "Open"
    field :upvotes_count, :integer, default: 0
    field :source_url, :string
    belongs_to :user, Onestack.Accounts.User
    has_many :comments, Onestack.Feedback.Comment

    timestamps()
  end

  def changeset(feedback, attrs) do
    feedback
    |> cast(attrs, [:title, :content, :status, :upvotes_count, :user_id, :source_url])
    |> validate_required([:title, :content])
    |> validate_url(:source_url)
  end

  defp validate_url(changeset, field) when is_atom(field) do
    validate_change(changeset, field, fn _, url ->
      if is_nil(url) or url == "" do
        []
      else
        case URI.parse(url) do
          %URI{scheme: scheme, host: host} when not is_nil(scheme) and not is_nil(host) ->
            []
          _ ->
            [{field, "must be a valid URL"}]
        end
      end
    end)
  end
end
