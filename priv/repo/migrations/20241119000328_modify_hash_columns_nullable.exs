defmodule Onestack.Repo.Migrations.ModifyHashColumnsNullable do
  use Ecto.Migration

  def change do
    alter table(:users) do
      modify :bcrypt_hash, :string, null: true
      modify :argon2id_hash, :string, null: true
      modify :pkbdf2_hash, :string, null: true
    end
  end
end
