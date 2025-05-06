defmodule Onestack.Repo.Migrations.CreateCustomers do
  use Ecto.Migration

  def change do
    create table(:customers) do
      add :email, :string
      add :customer_id, :string
      add :products, {:array, :string}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customers, [:customer_id])
    create unique_index(:customers, [:email])
  end
end
