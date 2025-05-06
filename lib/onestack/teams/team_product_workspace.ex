defmodule Onestack.Teams.TeamProductWorkspace do
  use Ecto.Schema
  import Ecto.Changeset

  schema "team_product_workspaces" do
    field :access_level, :string
    field :team_product_id, :id
    field :workspace_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team_product_workspace, attrs) do
    team_product_workspace
    |> cast(attrs, [:access_level])
    |> validate_required([:access_level])
  end
end
