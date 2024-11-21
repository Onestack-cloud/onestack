defmodule Onestack.Teams.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "invitations" do
    field :invitation_id, :string
    field :admin_email, :string
    field :recipient_email, :string
    field :accepted_at, :naive_datetime
    field :expires_at, :naive_datetime

    timestamps()
  end

  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:admin_email, :invitation_id, :recipient_email])
    |> validate_required([:admin_email, :invitation_id, :recipient_email])
    |> validate_format(:admin_email, ~r/^[^\s]+@[^\s]+$/)
    # 7 days
    |> put_change(
      :expires_at,
      NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      |> NaiveDateTime.add(7 * 24 * 60 * 60)
    )
  end
end
