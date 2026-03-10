defmodule Onestack.CatalogMonthlyFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Onestack.CatalogMonthly` context.
  """

  @doc """
  Generate a product.
  """
  def product_fixture(attrs \\ %{}) do
    {:ok, product} =
      attrs
      |> Enum.into(%{
        closed_source_name: "some closed_source_name",
        onestack_product_name: "some_product",
        closed_source_user_price: "120.5",
        closed_source_currency: "USD",
        icon_name: "box",
        feature_description: "some_feature"
      })
      |> Onestack.CatalogMonthly.create_product()

    product
  end
end
