defmodule Onestack.Teams.TeamProduct do
  use Ecto.Schema
  import Ecto.Changeset

  schema "team_products" do
    field :access_level, :string
    field :team_id, :id
    field :product_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team_product, attrs) do
    team_product
    |> cast(attrs, [:access_level])
    |> validate_required([:access_level])
  end
end
