defmodule Onestack.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations) do
      add :invitation_id, :string, null: false
      add :admin_email, :string, null: false
      add :recipient_email, :string, null: false

      add :accepted_at, :naive_datetime
      add :expires_at, :naive_datetime

      timestamps()
    end

    create unique_index(:invitations, [:invitation_id])
  end
end
