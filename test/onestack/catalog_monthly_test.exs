defmodule Onestack.CatalogMonthlyTest do
  use Onestack.DataCase

  alias Onestack.CatalogMonthly

  describe "products" do
    alias Onestack.CatalogMonthly.ComparisonProduct

    import Onestack.CatalogMonthlyFixtures

    @invalid_attrs %{
      category: nil,
      closed_source_name: nil,
      open_source_name: nil,
      closed_source_userprice: nil,
      open_source_fixed_price: nil,
      usd_to_aud: nil,
      closed_source_currency: nil,
      open_source_currency: nil
    }

    test "list_products/0 returns all products" do
      product = product_fixture()
      assert CatalogMonthly.list_products() == [product]
    end

    test "get_product!/1 returns the product with given id" do
      product = product_fixture()
      assert CatalogMonthly.get_product!(product.id) == product
    end

    test "create_product/1 with valid data creates a product" do
      valid_attrs = %{
        category: "some category",
        closed_source_name: "some closed_source_name",
        open_source_name: "some open_source_name",
        closed_source_userprice: "120.5",
        open_source_fixed_price: "120.5",
        usd_to_aud: "120.5",
        closed_source_currency: "some closed_source_currency",
        open_source_currency: "some open_source_currency"
      }

      assert {:ok, %ComparisonProduct{} = product} = CatalogMonthly.create_product(valid_attrs)
      assert product.category == "some category"
      assert product.closed_source_name == "some closed_source_name"
      assert product.open_source_name == "some open_source_name"
      assert product.closed_source_userprice == Decimal.new("120.5")
      assert product.open_source_fixed_price == Decimal.new("120.5")
      assert product.usd_to_aud == Decimal.new("120.5")
      assert product.closed_source_currency == "some closed_source_currency"
      assert product.open_source_currency == "some open_source_currency"
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = CatalogMonthly.create_product(@invalid_attrs)
    end

    test "update_product/2 with valid data updates the product" do
      product = product_fixture()

      update_attrs = %{
        category: "some updated category",
        closed_source_name: "some updated closed_source_name",
        open_source_name: "some updated open_source_name",
        closed_source_userprice: "456.7",
        open_source_fixed_price: "456.7",
        usd_to_aud: "456.7",
        closed_source_currency: "some updated closed_source_currency",
        open_source_currency: "some updated open_source_currency"
      }

      assert {:ok, %ComparisonProduct{} = product} = CatalogMonthly.update_product(product, update_attrs)
      assert product.category == "some updated category"
      assert product.closed_source_name == "some updated closed_source_name"
      assert product.open_source_name == "some updated open_source_name"
      assert product.closed_source_userprice == Decimal.new("456.7")
      assert product.open_source_fixed_price == Decimal.new("456.7")
      assert product.usd_to_aud == Decimal.new("456.7")
      assert product.closed_source_currency == "some updated closed_source_currency"
      assert product.open_source_currency == "some updated open_source_currency"
    end

    test "update_product/2 with invalid data returns error changeset" do
      product = product_fixture()
      assert {:error, %Ecto.Changeset{}} = CatalogMonthly.update_product(product, @invalid_attrs)
      assert product == CatalogMonthly.get_product!(product.id)
    end

    test "delete_product/1 deletes the product" do
      product = product_fixture()
      assert {:ok, %ComparisonProduct{}} = CatalogMonthly.delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> CatalogMonthly.get_product!(product.id) end
    end

    test "change_product/1 returns a product changeset" do
      product = product_fixture()
      assert %Ecto.Changeset{} = CatalogMonthly.change_product(product)
    end
  end
end
