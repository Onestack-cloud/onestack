defmodule Onestack.Payments.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "payments" do
    field :name, :string
    field :amount, :integer
    field :payment_intent_id, :string
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [:amount, :name, :payment_intent_id])
    |> validate_required([:amount, :name, :payment_intent_id])
  end
end
