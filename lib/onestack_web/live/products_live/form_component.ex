defmodule OnestackWeb.ProductLive.FormComponent do
  use OnestackWeb, :live_component

  alias Onestack.CatalogMonthly

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage product records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="product-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:category]} type="text" label="Category" phx-debounce="blur" />
        <.input field={@form[:closed_source_name]} type="text" label="Closed source name" />
        <.input field={@form[:open_source_name]} type="text" label="Open source name" />
        <.input
          field={@form[:closed_source_user_price]}
          type="number"
          label="Closed source userprice"
          step="any"
        />
        <.input
          field={@form[:open_source_fixed_price]}
          type="number"
          label="Open source fixed price"
          step="any"
        />
        <.input field={@form[:usd_to_aud]} type="number" label="Usd to aud" step="any" />
        <.input field={@form[:closed_source_currency]} type="text" label="Closed source currency" />
        <.input field={@form[:open_source_currency]} type="text" label="Open source currency" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Product</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{product: product} = assigns, socket) do
    changeset = CatalogMonthly.change_product(product)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"product" => product_params}, socket) do
    changeset =
      socket.assigns.product
      |> CatalogMonthly.change_product(product_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"product" => product_params}, socket) do
    save_product(socket, socket.assigns.action, product_params)
  end

  defp save_product(socket, :edit, product_params) do
    case CatalogMonthly.update_product(socket.assigns.product, product_params) do
      {:ok, product} ->
        notify_parent({:saved, product})

        {:noreply,
         socket
         |> put_flash(:info, "Product updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_product(socket, :new, product_params) do
    case CatalogMonthly.create_product(product_params) do
      {:ok, product} ->
        notify_parent({:saved, product})

        {:noreply,
         socket
         |> put_flash(:info, "Product created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
