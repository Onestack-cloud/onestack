defmodule Onestack.CatalogMonthly.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :category, :string
    field :closed_source_name, :string
    field :open_source_name, :string
    field :closed_source_user_price, :decimal
    field :open_source_fixed_price, :decimal
    field :usd_to_aud, :decimal, default: 1.52
    field :closed_source_currency, :string
    field :open_source_currency, :string
    field :closed_source_user_price_aud, :decimal

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :category,
      :closed_source_name,
      :open_source_name,
      :closed_source_user_price,
      :open_source_fixed_price,
      :usd_to_aud,
      :closed_source_currency,
      :open_source_currency
    ])
    |> validate_required([
      :category,
      :closed_source_name,
      :open_source_name,
      :closed_source_user_price,
      :open_source_fixed_price,
      :usd_to_aud,
      :closed_source_currency,
      :open_source_currency
    ])
    |> calculate_aud_prices()
  end

  defp calculate_aud_prices(changeset) do
    closed_source_user_price = get_field(changeset, :closed_source_user_price)
    usd_to_aud = get_field(changeset, :usd_to_aud)
    usd_to_aud_decimal = Decimal.from_float(usd_to_aud)

    closed_source_user_price_aud =
      if get_field(changeset, :closed_source_currency) == "USD" do
        closed_source_user_price
        |> Decimal.mult(usd_to_aud_decimal)
        |> Decimal.round(2)
      else
        closed_source_user_price
      end

    changeset
    |> put_change(:closed_source_user_price_aud, closed_source_user_price_aud)
  end
end
