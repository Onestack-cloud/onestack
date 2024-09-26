defmodule Onestack.MatrixAccounts.MatrixUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "matrix_users" do
    field :email, :string
    field :matrix_id, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(matrix_user, attrs) do
    matrix_user
    |> cast(attrs, [:email, :matrix_id, :active])
    |> validate_required([:email, :matrix_id])
  end
end
