defmodule OnestackWeb.OnestackAdmin.ComparisonProductsLive do
  use OnestackWeb, :live_view
  alias Onestack.CatalogMonthly
  alias Onestack.CatalogMonthly.ComparisonProduct

  # Add your admin emails here
  @admin_emails ["ben@onestack.cloud", "jawed-sketch-kite@duck.com", "george@onestack.cloud"]

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Onestack.Accounts.get_user_by_session_token(user_token)
      end

    if current_user && current_user.email in @admin_emails do
      if connected?(socket), do: Phoenix.PubSub.subscribe(Onestack.PubSub, "comparison_products")

      {:ok,
       assign(socket,
         current_user: current_user,
         products: list_products(),
         page_title: "Admin - Comparison Products",
         modal: nil,
         changeset: nil
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, "Unauthorized access")
       |> redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, socket |> assign(current_path: URI.parse(uri).path)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    product = CatalogMonthly.get_product!(id)
    {:ok, _} = CatalogMonthly.delete_product(product)

    {:noreply,
     socket
     |> put_flash(:info, "Product comparison deleted successfully")
     |> assign(products: list_products())}
  end

  def handle_event("new", _params, socket) do
    changeset = CatalogMonthly.change_product(%ComparisonProduct{})
    {:noreply, assign(socket, modal: :new, changeset: changeset)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    product = CatalogMonthly.get_product!(id)
    changeset = CatalogMonthly.change_product(product)
    {:noreply, assign(socket, modal: :edit, changeset: changeset, product: product)}
  end

  def handle_event("save", %{"comparison_product" => product_params}, socket) do
    case socket.assigns.modal do
      :new -> create_product(socket, product_params)
      :edit -> update_product(socket, socket.assigns.product, product_params)
    end
  end

  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, modal: nil, changeset: nil)}
  end

  @impl true
  def handle_info({:product_updated, _product}, socket) do
    {:noreply, assign(socket, products: list_products())}
  end

  defp list_products do
    CatalogMonthly.list_products()
  end

  defp create_product(socket, product_params) do
    case CatalogMonthly.create_product(product_params) do
      {:ok, product} ->
        Phoenix.PubSub.broadcast(
          Onestack.PubSub,
          "comparison_products",
          {:product_updated, product}
        )

        {:noreply,
         socket
         |> put_flash(:info, "Product comparison created successfully")
         |> assign(modal: nil, products: list_products())}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp update_product(socket, product, product_params) do
    case CatalogMonthly.update_product(product, product_params) do
      {:ok, product} ->
        Phoenix.PubSub.broadcast(
          Onestack.PubSub,
          "comparison_products",
          {:product_updated, product}
        )

        {:noreply,
         socket
         |> put_flash(:info, "Product comparison updated successfully")
         |> assign(modal: nil, products: list_products())}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
