defmodule Onestack.Subscriptions.SubscriptionMember do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscription_members" do
    field :status, :string
    field :email, :string
    field :subscription_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(subscription_member, attrs) do
    subscription_member
    |> cast(attrs, [:email, :status])
    |> validate_required([:email, :status])
  end
end
