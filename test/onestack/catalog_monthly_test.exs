defmodule Onestack.CatalogMonthlyTest do
  use Onestack.DataCase

  alias Onestack.CatalogMonthly

  describe "products" do
    alias Onestack.CatalogMonthly.ComparisonProduct

    import Onestack.CatalogMonthlyFixtures

    @invalid_attrs %{
      closed_source_name: nil,
      onestack_product_name: nil,
      closed_source_user_price: nil,
      closed_source_currency: nil,
      icon_name: nil,
      feature_description: nil
    }

    test "list_products/0 returns all products" do
      product = product_fixture()
      [listed] = CatalogMonthly.list_products()
      assert listed.id == product.id
      assert listed.closed_source_name == product.closed_source_name
    end

    test "get_product!/1 returns the product with given id" do
      product = product_fixture()
      assert CatalogMonthly.get_product!(product.id) == product
    end

    test "create_product/1 with valid data creates a product" do
      valid_attrs = %{
        closed_source_name: "some closed_source_name",
        onestack_product_name: "some_product",
        closed_source_user_price: "120.5",
        closed_source_currency: "USD",
        icon_name: "box",
        feature_description: "some_feature"
      }

      assert {:ok, %ComparisonProduct{} = product} = CatalogMonthly.create_product(valid_attrs)
      assert product.closed_source_name == "some closed_source_name"
      assert product.onestack_product_name == "some_product"
      assert product.closed_source_user_price == Decimal.new("120.5")
      assert product.closed_source_currency == "USD"
      assert product.icon_name == "box"
      assert product.feature_description == "some_feature"
    end

    test "create_product/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = CatalogMonthly.create_product(@invalid_attrs)
    end

    test "update_product/2 with valid data updates the product" do
      product = product_fixture()

      update_attrs = %{
        closed_source_name: "updated closed_source_name",
        onestack_product_name: "updated_product",
        closed_source_user_price: "456.7",
        closed_source_currency: "AUD",
        icon_name: "star",
        feature_description: "updated_feature"
      }

      assert {:ok, %ComparisonProduct{} = product} =
               CatalogMonthly.update_product(product, update_attrs)

      assert product.closed_source_name == "updated closed_source_name"
      assert product.onestack_product_name == "updated_product"
      assert product.closed_source_user_price == Decimal.new("456.7")
      assert product.closed_source_currency == "AUD"
      assert product.icon_name == "star"
      assert product.feature_description == "updated_feature"
    end

    test "update_product/2 with invalid data returns error changeset" do
      product = product_fixture()

      assert {:error, %Ecto.Changeset{}} =
               CatalogMonthly.update_product(product, %{onestack_product_name: nil, icon_name: nil})

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
