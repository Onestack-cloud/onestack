defmodule OnestackWeb.ProductCostComparisonLive do
  use OnestackWeb, :live_view

  import Ecto.Query
  alias Onestack.Repo
  alias Onestack.CatalogMonthly.Product

  alias Onestack.CatalogMonthly

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-full">
      <div class="container m-4 mx-auto flex justify-center">
        <div class="flex flex-col md:flex-row items-center">
          <div class="md:w-1/2 mb-8 md:mb-0 text-center md:text-left">
            <h1 class="text-4xl font-bold mb-4 font-pixel_title text-white">
              All your software tools in one platform
            </h1>
            <p class="text-lg">
              Hosting the the best software tools at a fraction of the price.
            </p>
            <div class="flex justify-center md:justify-start mt-10">
              <button class="btn btn-outline text-base">
                <a href="https://app.formbricks.com/s/clvf58ifk09j614804k6tk7jz" target="blank">
                  Sign up for early access
                </a>
              </button>
            </div>
          </div>
          <div class="md:ml-10 md:w-2/3">
            <img src={~p"/images/group.svg"} alt="Logo" class="h-15 w-full object-cover" />
          </div>
        </div>
      </div>
      <h1 class="text-4xl font-bold my-12 text-center mx-auto font-pixel_title" id="calculator">
        See how much you can save
      </h1>

      <%!-- <div class="mockup-code object-contain">
      <pre class="bg-secondary text-info-content"><code>Enter your team size and select your software needs \</code></pre>
      <pre class="bg-secondary text-info-content"><code>to see two key figures:</code></pre>

      <pre data-prefix="1."><code>Our Price ($10 per product for every 10 users)</code></pre>
      <pre data-prefix="2."><code>Monthly Savings (dollars and percentage saved compared to \</code></pre>
      <pre data-prefix="2."><code>closed-source software)</code></pre>
    </div> --%>
      <div class="flex items-center gap-6 p-6 bg-base-200 rounded border-t-4 border-bg-primary">
        <i class="fa-solid fa-circle-info text-2xl text-info"></i>

        <div class="flex flex-col">
          <h3 class="font-bold">
            Enter your team size and select your software needs to see two key figures
          </h3>
          <ul class="list-disc">
            <li>Our Price ($10 per product for every 10 users)</li>
            <li>Monthly Savings (dollars and percentage saved compared to closed-source software)</li>
          </ul>
        </div>
      </div>

      <div class="my-12 mx-auto px-4">
        <h2 class="card-title">How big is your team?</h2>
        <form phx-change="change" id="form">
          <div class="flex items-center justify-between">
            <input
              id="slider"
              type="range"
              min="1"
              max="20"
              value={@num_users}
              class="range w-full"
              name="num_users"
            />
            <h2 class="ml-4"><%= @num_users %></h2>
          </div>
        </form>
      </div>
      <%!-- <h3 class="card-title text-center">Search by</h3> --%>

      <div class="join mx-auto flex justify-center">
        <input
          class="join-item btn text-base"
          type="radio"
          name="search_selection"
          aria-label="Products"
          phx-click="select_search"
          value="products"
          checked={@product_category_search == "products"}
        />
        <input
          class="join-item btn text-base"
          type="radio"
          name="search_selection"
          aria-label="Categories"
          phx-click="select_search"
          value="categories"
          checked={@product_category_search == "categories"}
        />
      </div>
      <div class="mt-6 mx-auto flex flex-wrap justify-center">
        <%= for product_or_category <- @products_or_categories do %>
          <input
            type="checkbox"
            class="btn btn-outline my-0.5 mx-1 text-base"
            phx-click="select_product_or_category"
            phx-value-product_or_category={product_or_category}
            aria-label={product_or_category}
            checked={product_or_category in @selected_products_or_categories}
          />
        <% end %>
      </div>
      <div class="my-12 mx-auto flex justify-center">
        <div class="stats stats-vertical md:stats-horizontal">
          <div class="stat">
            <div class="stat-title">Monthly savings</div>
            <div class="stat-value">$<%= @savings %></div>
            <div class="stat-desc">
              <%= @savings_percent %>% saved compared to closed source
            </div>
            <div class="stat-actions">
              <button class="btn btn-outline btn-sm">
                <a href="https://app.formbricks.com/s/clvf58ifk09j614804k6tk7jz" target="blank">
                  Sign up for early access
                </a>
              </button>
            </div>
          </div>
          <div class="stat">
            <div class="stat-title">Our price</div>
            <div class="stat-value p mb-16">$<%= @total_costs[:open_source] %></div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    products = CatalogMonthly.list_products()

    product_categories =
      products
      |> Enum.map(fn product -> product.category end)
      |> Enum.uniq()

    {:ok,
     assign(socket,
       selected_products_or_categories: [],
       num_users: "2",
       chart_data: %{},
       total_costs: %{:open_source => 0},
       savings: 0,
       products_or_categories: product_categories,
       products: products,
       savings_percent: 0,
       product_category_search: "categories"
     )}
  end

  @impl true
  def handle_event(
        "select_product_or_category",
        %{"product_or_category" => product_or_category},
        socket
      ) do
    selected_products_or_categories = socket.assigns.selected_products_or_categories
    IO.inspect(product_or_category)

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

    IO.inspect(total_costs)

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
      from p in Product,
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
      from p in Product,
        where: p.closed_source_name in ^products,
        select: %{
          closed_source_name: p.closed_source_name,
          closed_source_user_price: p.closed_source_user_price_aud,
          open_source_fixed_price: p.open_source_fixed_price
        }

    Repo.all(query)
  end
end
