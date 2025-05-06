defmodule OnestackWeb.ProductLiveTest do
  use OnestackWeb.ConnCase

  import Phoenix.LiveViewTest
  import Onestack.CatalogMonthlyFixtures

  @create_attrs %{
    category: "some category",
    closed_source_name: "some closed_source_name",
    open_source_name: "some open_source_name",
    closed_source_userprice: "120.5",
    open_source_fixed_price: "120.5",
    usd_to_aud: "120.5",
    closed_source_currency: "some closed_source_currency",
    open_source_currency: "some open_source_currency"
  }
  @update_attrs %{
    category: "some updated category",
    closed_source_name: "some updated closed_source_name",
    open_source_name: "some updated open_source_name",
    closed_source_userprice: "456.7",
    open_source_fixed_price: "456.7",
    usd_to_aud: "456.7",
    closed_source_currency: "some updated closed_source_currency",
    open_source_currency: "some updated open_source_currency"
  }
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

  defp create_product(_) do
    product = product_fixture()
    %{product: product}
  end

  describe "Index" do
    setup [:create_product]

    test "lists all products", %{conn: conn, product: product} do
      {:ok, _index_live, html} = live(conn, ~p"/products")

      assert html =~ "Listing Products"
      assert html =~ product.category
    end

    test "saves new product", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/products")

      assert index_live |> element("a", "New Product") |> render_click() =~
               "New Product"

      assert_patch(index_live, ~p"/products/new")

      assert index_live
             |> form("#product-form", product: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#product-form", product: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/products")

      html = render(index_live)
      assert html =~ "Product created successfully"
      assert html =~ "some category"
    end

    test "updates product in listing", %{conn: conn, product: product} do
      {:ok, index_live, _html} = live(conn, ~p"/products")

      assert index_live |> element("#products-#{product.id} a", "Edit") |> render_click() =~
               "Edit Product"

      assert_patch(index_live, ~p"/products/#{product}/edit")

      assert index_live
             |> form("#product-form", product: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#product-form", product: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/products")

      html = render(index_live)
      assert html =~ "Product updated successfully"
      assert html =~ "some updated category"
    end

    test "deletes product in listing", %{conn: conn, product: product} do
      {:ok, index_live, _html} = live(conn, ~p"/products")

      assert index_live |> element("#products-#{product.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#products-#{product.id}")
    end
  end

  describe "Show" do
    setup [:create_product]

    test "displays product", %{conn: conn, product: product} do
      {:ok, _show_live, html} = live(conn, ~p"/products/#{product}")

      assert html =~ "Show Product"
      assert html =~ product.category
    end

    test "updates product within modal", %{conn: conn, product: product} do
      {:ok, show_live, _html} = live(conn, ~p"/products/#{product}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Product"

      assert_patch(show_live, ~p"/products/#{product}/show/edit")

      assert show_live
             |> form("#product-form", product: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#product-form", product: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/products/#{product}")

      html = render(show_live)
      assert html =~ "Product updated successfully"
      assert html =~ "some updated category"
    end
  end
end
