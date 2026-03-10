defmodule Onestack.Repo.Migrations.AddInfisicalToProductsCentral do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO products_central (onestack_product_name, closed_source_name, closed_source_user_price, closed_source_currency, feature_description, icon_name, inserted_at, updated_at)
    VALUES ('Infisical', 'doppler.com', 18, 'USD', 'secrets_management', 'lock-keyhole', datetime('now'), datetime('now'));
    """
  end

  def down do
    execute """
    DELETE FROM products_central WHERE onestack_product_name = 'Infisical';
    """
  end
end
