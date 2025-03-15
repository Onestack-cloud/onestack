defmodule OnestackWeb.LandingLive do
  alias Onestack.CatalogMonthly.ComparisonProduct
  use OnestackWeb, :live_view

  import Ecto.Query
  alias Onestack.Repo
  alias Onestack.Accounts

  alias Onestack.CatalogMonthly

  alias OnestackWeb.Live.LandingLive.TestimonialData

  @impl true
  def mount(_params, session, socket) do
    products = CatalogMonthly.list_products()
    features = CatalogMonthly.ProductMetadata.all_products()
    testimonial_cards = TestimonialData.testimonial_cards()

    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Accounts.get_user_by_session_token(user_token)
      end

    prepared_products =
      Enum.map(products, fn product ->
        product
        |> Map.from_struct()
        |> Map.drop([:__meta__])
        |> Map.new(fn {k, v} ->
          {k,
           if is_struct(v, Decimal) do
             Decimal.to_float(v)
           else
             v
           end}
        end)
      end)

    {:ok,
     assign(socket,
       products: products,
       current_user: current_user,
       prepared_products: Jason.encode!(prepared_products),
       features: features,
       testimonial_cards: testimonial_cards
     )}
  end

  @impl true
  def handle_event(
        "select_product_or_category",
        %{"product_or_category" => product_or_category},
        socket
      ) do
    selected_products_or_categories = socket.assigns.selected_products_or_categories
    # IO.inspect(product_or_category)

    selected_products_or_categories =
      if product_or_category in selected_products_or_categories do
        selected_products_or_categories -- [product_or_category]
      else
        [product_or_category | selected_products_or_categories]
      end

    num_users = socket.assigns.num_users
    {num_users, _} = Integer.parse(num_users)

    %{total_costs: total_costs, savings: savings, savings_percent: savings_percent} =
      calculate_total_costs_and_savings(selected_products_or_categories, num_users, socket)

    # IO.inspect(total_costs)

    {:noreply,
     assign(socket,
       selected_products_or_categories: selected_products_or_categories,
       total_costs: total_costs,
       savings: savings,
       savings_percent: savings_percent
     )}
  end

  @impl true
  def handle_event("change", %{"_target" => ["num_users"], "num_users" => value}, socket) do
    {num_users, _} = Integer.parse(value)
    selected_products_or_categories = socket.assigns.selected_products_or_categories

    %{total_costs: total_costs, savings: savings, savings_percent: savings_percent} =
      calculate_total_costs_and_savings(selected_products_or_categories, num_users, socket)

    {:noreply,
     assign(socket,
       num_users: value,
       total_costs: total_costs,
       savings: savings,
       savings_percent: savings_percent
     )}
  end

  # @impl true
  # def handle_event("generate_chart", _params, socket) do
  #   # Perform the necessary calculations and update the chart data and total costs
  #   # based on the selected categories and number of users
  #   # You can use the data from your previous example and adapt it to LiveView
  #   # Replace with your calculated chart data
  #   chart_data = %{}
  #   # Replace with your calculated total costs
  #   total_costs = %{}
  #   {:noreply, assign(socket, chart_data: chart_data, total_costs: total_costs)}
  # end

  def handle_event("select_search", %{"value" => selection}, socket) do
    IO.inspect(socket.assigns.product_category_search)
    # Handle the selected search option
    case selection do
      "products" ->
        # Perform actions for products search
        products = CatalogMonthly.list_products()

        products =
          products
          |> Enum.map(fn product -> product.closed_source_name end)
          |> Enum.uniq()

        {:noreply,
         assign(socket,
           products_or_categories: products,
           selected_products_or_categories: [],
           product_category_search: selection
         )}

      "categories" ->
        # Perform actions for categories search

        products = CatalogMonthly.list_products()

        categories =
          products
          |> Enum.map(fn product -> product.category end)
          |> Enum.uniq()

        {:noreply,
         assign(socket,
           products_or_categories: categories,
           selected_products_or_categories: [],
           product_category_search: selection
         )}
    end
  end

  defp calculate_total_costs_and_savings(selected_products_or_categories, num_users, socket) do
    case socket.assigns.product_category_search do
      "products" ->
        product_prices = get_product_prices(selected_products_or_categories)
        calculate_costs_and_savings(product_prices, num_users)

      "categories" ->
        category_prices = get_average_prices(selected_products_or_categories)
        calculate_costs_and_savings(category_prices, num_users)
    end
  end

  defp calculate_costs_and_savings(prices, num_users) do
    total_costs =
      Enum.reduce(
        prices,
        %{closed_source: Decimal.new(0), open_source: Decimal.new(0)},
        fn %{
             closed_source_user_price: closed_source_price,
             open_source_fixed_price: open_source_price
           },
           acc ->
          closed_source_cost = Decimal.mult(closed_source_price, Decimal.new(num_users))
          # Calculate the number of steps (every 10 users)
          steps = div(num_users - 1, 10) + 1
          open_source_cost = Decimal.mult(open_source_price, Decimal.new(steps))

          %{
            closed_source: Decimal.add(acc.closed_source, closed_source_cost),
            open_source: Decimal.add(acc.open_source, open_source_cost)
          }
        end
      )

    savings = Decimal.sub(total_costs.closed_source, total_costs.open_source)

    savings_percent =
      if Decimal.eq?(total_costs.closed_source, 0) do
        "0"
      else
        savings_percent_decimal =
          savings
          |> Decimal.div(total_costs.closed_source)
          |> Decimal.mult(100)

        savings_percent_string =
          savings_percent_decimal
          |> Decimal.round(2)
          |> Decimal.to_string(:normal)

        savings_percent_formatted =
          case String.split(savings_percent_string, ".") do
            [whole_part] ->
              whole_part <> ".00"

            [whole_part, decimal_part] ->
              decimal_part_padded = String.pad_trailing(decimal_part, 2, "0")
              whole_part <> "." <> String.slice(decimal_part_padded, 0, 2)
          end

        savings_percent_formatted
      end

    %{
      total_costs: total_costs,
      savings: savings,
      savings_percent: savings_percent
    }
  end

  def get_average_prices(categories) do
    query =
      from p in ComparisonProduct,
        where: p.category in ^categories,
        group_by: p.category,
        select: %{
          category: p.category,
          closed_source_user_price: avg(p.closed_source_user_price_aud),
          open_source_fixed_price: avg(p.open_source_fixed_price)
        }

    Repo.all(query)
  end

  def get_product_prices(products) do
    query =
      from p in ComparisonProduct,
        where: p.closed_source_name in ^products,
        select: %{
          closed_source_name: p.closed_source_name,
          closed_source_user_price: p.closed_source_user_price_aud,
          open_source_fixed_price: p.open_source_fixed_price
        }

    Repo.all(query)
  end
end
