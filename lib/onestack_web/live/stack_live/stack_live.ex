defmodule OnestackWeb.StackLive do
  use OnestackWeb, :live_view

  alias Onestack.StripeCache

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:selected_product_categories, [])
     |> assign(:products, StripeCache.list_products())
     |> assign(:selected_products, [])}
  end
end
