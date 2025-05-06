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
        category: "some category",
        closed_source_currency: "some closed_source_currency",
        closed_source_name: "some closed_source_name",
        closed_source_user_price: "120.5",
        open_source_currency: "some open_source_currency",
        open_source_fixed_price: "120.5",
        open_source_name: "some open_source_name",
        usd_to_aud: "120.5"
      })
      |> Onestack.CatalogMonthly.create_product()

    product
  end
end
