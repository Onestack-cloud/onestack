defmodule Onestack.Repo.Migrations.FixSelectedProductsColumnType do
  use Ecto.Migration

  def change do
    # SQLite doesn't support ALTER COLUMN, so we need to recreate the table
    # Since the table is empty, this is safe
    
    # Drop and recreate the table with correct column type
    drop_if_exists table(:subscriptions)
    
    create table(:subscriptions) do
      add :status, :string
      add :stripe_subscription_id, :string
      add :stripe_customer_id, :string
      add :customer_email, :string
      add :plan_type, :string
      add :num_users, :integer, default: 1
      add :selected_products, {:array, :string}  # Fixed: was {:array, :integer}
      add :metadata, :map, default: %{}
      add :user_id, references(:users, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end
    
    create unique_index(:subscriptions, [:stripe_subscription_id])
    create index(:subscriptions, [:user_id])
  end
end
