defmodule Onestack.Subscriptions.Customer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "customers" do
    field :email, :string
    field :customer_id, :string
    field :products, {:array, :string}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:email, :customer_id, :products])
    |> validate_required([:email, :customer_id, :products])
    |> unique_constraint(:customer_id)
    |> unique_constraint(:email)
  end
end
