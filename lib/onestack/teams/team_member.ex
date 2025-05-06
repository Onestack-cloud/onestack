defmodule Onestack.Teams.TeamMember do
  use Ecto.Schema
  import Ecto.Changeset

  schema "team_members" do
    field :role, :string
    field :team_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team_member, attrs) do
    team_member
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end
end
