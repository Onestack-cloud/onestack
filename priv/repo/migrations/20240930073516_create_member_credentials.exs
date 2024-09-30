defmodule Onestack.Repo.Migrations.CreateMemberCredentials do
  use Ecto.Migration

  def change do
    create table(:member_credentials) do
      add :job_id, :string
      add :email, :string
      add :product, :string
      add :password, :string
      add :hashed_password, :string
      add :salt, :string
      add :status, :string

      timestamps(type: :utc_datetime)
    end
  end
end
