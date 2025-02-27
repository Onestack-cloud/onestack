defmodule Onestack.Organisations.OrganisationMember do
  use Ecto.Schema
  import Ecto.Changeset

  schema "organisation_members" do
    field :role, :string
    field :email, :string
    field :organisation_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(organisation_member, attrs) do
    organisation_member
    |> cast(attrs, [:role, :email])
    |> validate_required([:role, :email])
  end
end
