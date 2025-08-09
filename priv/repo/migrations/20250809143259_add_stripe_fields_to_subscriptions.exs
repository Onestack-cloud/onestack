defmodule Onestack.Repo.Migrations.AddStripeFieldsToSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      add :stripe_subscription_id, :string
      add :stripe_customer_id, :string  
      add :customer_email, :string
      add :plan_type, :string
      add :num_users, :integer, default: 1
      add :selected_products, {:array, :integer}
      add :metadata, :map, default: %{}
    end
    
    create unique_index(:subscriptions, [:stripe_subscription_id])
    create index(:subscriptions, [:customer_email])
    create index(:subscriptions, [:plan_type])
  end
end
