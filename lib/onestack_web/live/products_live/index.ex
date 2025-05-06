defmodule OnestackWeb.ProductLive.Index do
  use OnestackWeb, :live_view

  alias Onestack.{StripeCache, Accounts}

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Accounts.get_user_by_session_token(user_token)
      end

    {:ok,
     socket
     |> assign(:selected_product_categories, [])
     |> assign(:products, Onestack.CatalogMonthly.list_products())
     |> assign(:current_user, current_user)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # defp apply_action(socket, :edit, %{"id" => id}) do
  #   socket
  #   |> assign(:page_title, "Edit Product")
  #   |> assign(:product, CatalogMonthly.get_product!(id))
  # end

  # defp apply_action(socket, :new, _params) do
  #   socket
  #   |> assign(:page_title, "New Product")
  #   |> assign(:product, %Product{})
  # end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Products")
    |> assign(:product, nil)
  end

  @impl true
  def handle_info({OnestackWeb.ProductLive.FormComponent, {:saved, product}}, socket) do
    {:noreply, stream_insert(socket, :products, product)}
  end

  # @impl true
  # def handle_event("delete", %{"id" => id}, socket) do
  #   product = CatalogMonthly.get_product!(id)
  #   {:ok, _} = CatalogMonthly.delete_product(product)

  #   {:noreply, stream_delete(socket, :products, product)}
  # end

  # def handle_event(
  #       "selected_product_category",
  #       %{"product_category" => product_category},
  #       socket
  #     ) do
  #   selected_product_categories = socket.assigns.selected_product_categories

  #   selected_product_categories =
  #     if product_category in selected_product_categories do
  #       selected_product_categories -- [product_category]
  #     else
  #       [product_category | selected_product_categories]
  #     end

  #   products = CatalogMonthly.list_products()

  #   filtered_products =
  #     products
  #     |> Enum.filter(fn product -> product.category in selected_product_categories end)

  #   # Reset the stream with the filtered products
  #   socket = socket |> stream(:products, filtered_products, reset: true)

  #   {:noreply,
  #    socket
  #    |> assign(:selected_product_categories, selected_product_categories)}
  # end
end
