defmodule Onestack.Repo.Migrations.CreateSubscriptionMembers do
  use Ecto.Migration

  def change do
    create table(:subscription_members) do
      add :email, :string
      add :status, :string
      add :subscription_id, references(:subscriptions, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:subscription_members, [:subscription_id])
  end

  def change do
    create table(:invitations) do
      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :inviter_id, references(:users, on_delete: :nilify_all)
      add :invitee_email, :string, null: false

      timestamps()
    end

    create unique_index(:invitations, [:token])
    create index(:invitations, [:inviter_id])
  end
end
