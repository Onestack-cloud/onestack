defmodule OnestackWeb.PricingLive do
  use OnestackWeb, :live_view

  def mount(_params, session, socket) do
    products = Onestack.CatalogMonthly.list_products()

    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Onestack.Accounts.get_user_by_session_token(user_token)
      end

    {:ok,
     assign(socket,
       selected_plan: "individual",
       selected_products: [],
       products: products,
       # Convert products list to a map for faster lookups
       products_by_id: Map.new(products, &{&1.id, &1}),
       # Start with OneStack view to highlight our benefits
       workflow_view: "onestack",
       # Track which feature is being highlighted
       active_feature: "security",
       # Track if the trial modal is open
       show_trial_modal: false,
       current_user: current_user
     )}
  end

  def handle_event("start_trial", _params, socket) do
    {:noreply, assign(socket, :show_trial_modal, true)}
  end

  def handle_event("close_trial_modal", _params, socket) do
    {:noreply, assign(socket, :show_trial_modal, false)}
  end

  def handle_event("highlight_feature", %{"feature" => feature}, socket) do
    {:noreply, assign(socket, :active_feature, feature)}
  end

  def handle_event("toggle_workflow_view", _params, socket) do
    new_view = if socket.assigns.workflow_view == "onestack", do: "traditional", else: "onestack"
    {:noreply, assign(socket, :workflow_view, new_view)}
  end

  def handle_event("set_plan", %{"plan" => plan}, socket) do
    {:noreply, assign(socket, :selected_plan, plan)}
  end

  def handle_event("toggle_product", %{"product" => product_id}, socket) do
    # Convert product_id to integer since it comes as string from the form
    product_id = String.to_integer(product_id)

    selected_products =
      if product_id in socket.assigns.selected_products do
        List.delete(socket.assigns.selected_products, product_id)
      else
        [product_id | socket.assigns.selected_products]
      end

    {:noreply, assign(socket, :selected_products, selected_products)}
  end

  defp get_product_price(index, plan_type) do
    case plan_type do
      "individual" -> Enum.at([8, 6, 4, 2, 2, 2], index, 2)
      "team" -> Enum.at([10, 8, 6, 6, 6, 6], index, 6)
    end
  end

  defp calculate_total(selected_products, plan_type) do
    selected_products
    |> Enum.with_index()
    |> Enum.reduce(0, fn {_product_id, index}, acc ->
      acc + get_product_price(index, plan_type)
    end)
  end

  defp calculate_savings(selected_products, products_by_id) do
    selected_products
    |> Enum.with_index()
    |> Enum.reduce(0, fn {product_id, index}, acc ->
      case Map.get(products_by_id, product_id) do
        nil ->
          acc

        product ->
          # Add the difference between closed source price and our price
          # Assuming all prices are in the same currency (USD)
          closed_source_price = Decimal.to_float(product.closed_source_user_price)
          our_price = get_product_price(index, "individual")
          acc + (closed_source_price - our_price)
      end
    end)
  end

  defp calculate_closed_source_total(selected_products, products_by_id) do
    selected_products
    |> Enum.reduce(0, fn product_id, acc ->
      case Map.get(products_by_id, product_id) do
        nil ->
          acc

        product ->
          # Sum up just the closed source prices
          closed_source_price = Decimal.to_float(product.closed_source_user_price)
          acc + closed_source_price
      end
    end)
  end

  defp get_total_time_saved(selected_products) do
    # Estimate 30 minutes saved per product per day
    minutes_per_day = length(selected_products) * 30
    hours_per_month = minutes_per_day * 30 / 60

    hours_per_month
  end
end
