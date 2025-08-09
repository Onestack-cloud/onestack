defmodule Onestack.Subscriptions.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    field :status, :string
    field :stripe_subscription_id, :string
    field :stripe_customer_id, :string
    field :customer_email, :string
    field :plan_type, :string # "individual" or "team"
    field :num_users, :integer, default: 1
    field :selected_products, {:array, :string}
    field :metadata, :map, default: %{}
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:status, :stripe_subscription_id, :stripe_customer_id, :customer_email, 
                    :plan_type, :num_users, :selected_products, :metadata, :user_id])
    |> validate_required([:status])
    |> validate_inclusion(:plan_type, ["individual", "team"])
    |> validate_number(:num_users, greater_than: 0)
    |> unique_constraint(:stripe_subscription_id)
  end
end
