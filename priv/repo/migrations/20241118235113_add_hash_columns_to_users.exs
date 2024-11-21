defmodule Onestack.Repo.Migrations.AddHashColumnsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :bcrypt_hash, :string, default: ""
      add :argon2id_hash, :string, default: ""
      add :pkbdf2_hash, :string, default: ""
    end
  end
end
