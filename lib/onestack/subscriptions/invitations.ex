defmodule Onestack.Subscriptions.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invitations" do
    field :token, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    field :invitee_email, :string
    belongs_to :inviter, Onestack.Accounts.User

    timestamps()
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:token, :expires_at, :used_at, :invitee_email, :inviter_id])
    |> validate_required([:token, :expires_at, :invitee_email, :inviter_id])
    |> unique_constraint(:token)
  end
end
