defmodule Onestack.CatalogMonthly.ComparisonProduct do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products_central" do
    field :closed_source_name, :string
    field :onestack_product_name, :string
    field :closed_source_user_price, :decimal
    field :closed_source_currency, :string
    field :icon_name, :string
    field :feature_description, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :closed_source_name,
      :onestack_product_name,
      :closed_source_user_price,
      :closed_source_currency,
      :icon_name,
      :feature_description
    ])
    |> validate_required([
      :onestack_product_name,
      :icon_name
    ])
  end

  # defp calculate_aud_prices(changeset) do
  #   closed_source_user_price = get_field(changeset, :closed_source_user_price)
  #   usd_to_aud = get_field(changeset, :usd_to_aud)

  #   closed_source_user_price_aud =
  #     if get_field(changeset, :closed_source_currency) == "USD" do
  #       closed_source_user_price
  #       |> Decimal.mult(usd_to_aud)
  #       |> Decimal.round(2)
  #     else
  #       closed_source_user_price
  #     end

  #   changeset
  #   |> put_change(:closed_source_user_price_aud, closed_source_user_price_aud)
  # end
end
