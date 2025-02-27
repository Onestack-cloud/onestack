defmodule Onestack.StripeCache do
  @moduledoc """
  StripeCache GenServer for managing Stripe prices and tax rates.
  """
  use GenServer
  require Logger

  alias Stripe.{Price, TaxRate, Product, Subscription, Customer}

  defstruct [
    :tax_rates,
    :prices,
    :products,
    :customers,
    :subscriptions,
    :combined_customers,
    :upcoming_invoices
  ]

  @refresh_interval :timer.minutes(30)

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns the list of active Stripe prices.

  ## Examples

      iex> list_prices()
      [%Stripe.Price{}, ...]

  """
  def list_prices do
    GenServer.call(__MODULE__, :list_prices)
  end

  @doc """
  Returns the list of all active stripe Products.

  ## Examples

      iex> list_products()
      [%Stripe.Product{}, ...]

  """
  def list_products do
    GenServer.call(__MODULE__, :list_products)
  end

  @doc """
  Returns the list of all active Stripe subscriptions.

  ## Examples

      iex> list_subscriptions()
      [%Stripe.Subscription{}, ...]

  """
  def list_subscriptions do
    GenServer.call(__MODULE__, :list_subscriptions)
  end

  def list_combined_customers do
    GenServer.call(__MODULE__, :list_combined_customers)
  end

  @doc """
  Returns the list of all active Stripe customers.

  ## Examples

      iex> list_customers()
      [%Stripe.Customer{}, ...]

  """
  def list_customers do
    GenServer.call(__MODULE__, :list_customers)
  end

  @doc """
  Returns the list of active Stripe tax rates.

  ## Examples

      iex> list_taxes()
      [%Stripe.TaxRate{}, ...]

  """
  def list_tax_rates do
    GenServer.call(__MODULE__, :list_tax_rates)
  end

  def update_cache_for_new_customer(customer_id) do
    GenServer.call(__MODULE__, {:update_customer, customer_id})
  end

  def delete_subscription_from_cache(subscription_id) do
    GenServer.call(__MODULE__, {:delete_subscription, subscription_id})
  end

  @doc """
  Returns a Stripe Price ID.

  ## Examples

      iex> get_price_id("feature-xyz")
      {:ok, "price_abc123"}

      iex> get_price_id("non-existant")
      {:error, "No Stripe price found with lookup_key matching: "non-existant""}

  """
  def get_price_id(lookup_key) do
    price =
      list_prices()
      |> Enum.find(fn x -> x.lookup_key == lookup_key end)

    case price do
      nil ->
        {:error, "No Stripe price found with lookup_key matching: #{lookup_key}"}

      _ ->
        {:ok, price.id}
    end
  end

  @doc """
  Returns a Stripe Tax Rate ID.

  ## Examples

      iex> get_tax_rate_id("feature-xyz")
      {:ok, "txr_abc123"}

      iex> get_tax_rate_id("non-existant")
      [warning]
      {:error, "No Stripe tax rate found with country matching: "non-existant""}

  """
  def get_tax_rate_id(country) do
    tax_rate =
      list_tax_rates()
      |> Enum.find(fn x -> x.country == country end)

    case tax_rate do
      nil ->
        {:error, "No Stripe tax rate found with country matching: #{country}"}

      _ ->
        {:ok, tax_rate.id}
    end
  end

  def update_cache_for_subscription(subscription_id) do
    GenServer.call(__MODULE__, {:update_subscription, subscription_id})
  end

  def get_upcoming_invoice(subscription_id) do
    GenServer.call(__MODULE__, {:get_upcoming_invoice, subscription_id})
  end

  @doc """
  Gets the subscription item price for a specific product in a subscription.
  Returns nil if the product is not in the subscription.
  """
  def get_subscription_item_price(subscription_id, product_id) do
    GenServer.call(__MODULE__, {:get_subscription_item_price, subscription_id, product_id})
  end

  @doc false
  def init(_state) do
    with {:ok, %{data: prices}} <- Price.list(%{active: true}),
         {:ok, %{data: tax_rates}} <- TaxRate.list(%{active: true}),
         {:ok, %{data: products}} <- Product.list(%{active: true}),
         {:ok, %{data: customers}} <- Customer.list(%{limit: 9999}),
         {:ok, %{data: subscriptions}} <- Subscription.list(%{limit: 9999}),
         upcoming_invoices <- fetch_upcoming_invoices(subscriptions),
         combined_customers =
           Onestack.CustomerCombiner.combine_customers(customers, subscriptions) do
      schedule_refresh()

      {:ok,
       %__MODULE__{
         prices: prices,
         tax_rates: tax_rates,
         products: products,
         customers: customers,
         subscriptions: subscriptions,
         combined_customers: combined_customers,
         upcoming_invoices: upcoming_invoices
       }}
    else
      {:error, error} ->
        raise "Failed to initialise StripeCache: #{error.code} (#{error.message}). Ensure you have set up the Stripe Secret environment variable."
    end
  end

  @doc false
  def handle_info(:refresh, state) do
    schedule_refresh()

    with {:ok, %{data: prices}} <- Price.list(%{active: true}),
         {:ok, %{data: tax_rates}} <- TaxRate.list(%{active: true}),
         {:ok, %{data: products}} <- Product.list(%{active: true}),
         {:ok, %{data: customers}} <- Customer.list(%{limit: 9999}),
         {:ok, %{data: subscriptions}} <- Subscription.list(%{limit: 9999}),
         upcoming_invoices <- fetch_upcoming_invoices(subscriptions),
         combined_customers =
           Onestack.CustomerCombiner.combine_customers(customers, subscriptions) do
      {:noreply,
       %__MODULE__{
         prices: prices,
         tax_rates: tax_rates,
         products: products,
         customers: customers,
         subscriptions: subscriptions,
         combined_customers: combined_customers,
         upcoming_invoices: upcoming_invoices
       }}
    else
      {:error, reason} ->
        Logger.warning("Failed to refresh StripeCache: #{reason}. Using old state")
        {:noreply, state}
    end
  end

  @doc false
  def handle_call(:list_prices, _from, %{prices: prices} = state) do
    {:reply, prices, state}
  end

  @doc false
  def handle_call(:list_products, _from, %{products: products} = state) do
    {:reply, products, state}
  end

  @doc false
  def handle_call(:list_tax_rates, _from, %{tax_rates: tax_rates} = state) do
    {:reply, tax_rates, state}
  end

  @doc false
  def handle_call(:list_subscriptions, _from, %{subscriptions: subscriptions} = state) do
    {:reply, subscriptions, state}
  end

  @doc false
  def handle_call(:list_customers, _from, %{customers: customers} = state) do
    {:reply, customers, state}
  end

  def handle_call({:get_subscription_item_price, subscription_id, product_id}, _from, state) do
    subscription = Enum.find(state.subscriptions, &(&1.id == subscription_id))
    
    price = case subscription do
      nil -> nil
      sub ->
        Enum.find_value(sub.items.data, fn item -> 
          if item.price.product == product_id, do: item.price.unit_amount
        end)
    end

    {:reply, price, state}
  end

  @doc false
  def handle_call(
        :list_combined_customers,
        _from,
        %{combined_customers: combined_customers} = state
      ) do
    {:reply, combined_customers, state}
  end

  def handle_call({:update_subscription, subscription_id}, from, state) do
    try do
      Logger.info("Updating subscription: #{subscription_id}")

      case Stripe.Subscription.retrieve(subscription_id, %{}, timeout: 10_000) do
        {:ok, updated_subscription} when not is_nil(updated_subscription) ->
          Logger.info("Retrieved subscription from Stripe: #{inspect(updated_subscription)}")

          if updated_subscription.status == "canceled" do
            Logger.info("Subscription #{subscription_id} is canceled. Deleting from cache.")
            {:ok, new_state} = handle_call({:delete_subscription, subscription_id}, from, state)
            {:reply, :ok, new_state}
          else
            updated_subscriptions = update_list(state.subscriptions, updated_subscription)
            Logger.info("Updated subscriptions list. New count: #{length(updated_subscriptions)}")

            updated_combined_customers =
              recalculate_combined_customers(state.customers, updated_subscriptions)

            Logger.info(
              "Recalculated combined customers. New count: #{length(updated_combined_customers)}"
            )

            updated_upcoming_invoices =
              case Stripe.Invoice.upcoming(%{subscription: subscription_id}) do
                {:ok, upcoming_invoice} ->
                  Map.put(state.upcoming_invoices, subscription_id, upcoming_invoice)

                {:error, _} ->
                  state.upcoming_invoices
              end

            new_state = %{
              state
              | subscriptions: updated_subscriptions,
                combined_customers: updated_combined_customers,
                upcoming_invoices: updated_upcoming_invoices
            }

            Logger.info(
              "State updated. New subscription count: #{length(new_state.subscriptions)}"
            )

            {:reply, :ok, new_state}
          end

        {:ok, nil} ->
          Logger.error("Retrieved nil subscription from Stripe for ID: #{subscription_id}")
          {:reply, {:error, :subscription_not_found}, state}

        {:error, reason} ->
          Logger.error(
            "Failed to update StripeCache for subscription #{subscription_id}: #{inspect(reason)}"
          )

          {:reply, {:error, reason}, state}
      end
    rescue
      e ->
        Logger.error("Unexpected error in update_subscription: #{inspect(e)}")
        {:reply, {:error, :unexpected_error}, state}
    end
  end

  def handle_call({:delete_subscription, subscription_id}, _from, state) do
    Logger.info("Deleting subscription: #{subscription_id}")

    updated_subscriptions = Enum.reject(state.subscriptions, &(&1.id == subscription_id))
    Logger.info("Updated subscriptions list. New count: #{length(updated_subscriptions)}")

    updated_combined_customers =
      recalculate_combined_customers(state.customers, updated_subscriptions)

    Logger.info(
      "Recalculated combined customers. New count: #{length(updated_combined_customers)}"
    )

    new_state = %{
      state
      | subscriptions: updated_subscriptions,
        combined_customers: updated_combined_customers
    }

    Logger.info("State updated. New subscription count: #{length(new_state.subscriptions)}")

    if length(state.subscriptions) == length(updated_subscriptions) do
      Logger.warning("Subscription #{subscription_id} was not found in the cache")
      {:reply, {:error, :not_found}, state}
    else
      {:reply, :ok, new_state}
    end
  end

  def handle_call({:update_customer, customer_id}, _from, state) do
    Logger.info("Updating customer: #{customer_id}")

    with {:ok, updated_customer} <- Stripe.Customer.retrieve(customer_id) do
      Logger.info("Retrieved customer from Stripe: #{inspect(updated_customer)}")

      updated_customers = update_list(state.customers, updated_customer)
      Logger.info("Updated customers list. New count: #{length(updated_customers)}")

      updated_combined_customers =
        recalculate_combined_customers(updated_customers, state.subscriptions)

      Logger.info(
        "Recalculated combined customers. New count: #{length(updated_combined_customers)}"
      )

      new_state = %{
        state
        | customers: updated_customers,
          combined_customers: updated_combined_customers
      }

      Logger.info("State updated. New customer count: #{length(new_state.customers)}")

      # Changed from {:noreply, new_state}
      {:reply, :ok, new_state}
    else
      {:error, reason} ->
        Logger.warning(
          "Failed to update StripeCache for customer #{customer_id}: #{inspect(reason)}"
        )

        # Changed from {:noreply, state}
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_upcoming_invoice, subscription_id}, _from, state) do
    invoice = Map.get(state.upcoming_invoices, subscription_id)
    {:reply, invoice, state}
  end

  defp update_list(list, updated_item) do
    if Enum.any?(list, fn item -> item.id == updated_item.id end) do
      Enum.map(list, fn item ->
        if item.id == updated_item.id, do: updated_item, else: item
      end)
    else
      [updated_item | list]
    end
  end

  defp fetch_upcoming_invoices(subscriptions) do
    subscriptions
    |> Enum.reduce(%{}, fn subscription, acc ->
      case Stripe.Invoice.upcoming(%{subscription: subscription.id}) do
        {:ok, upcoming_invoice} -> Map.put(acc, subscription.id, upcoming_invoice)
        {:error, _error} -> acc
      end
    end)
  end

  defp recalculate_combined_customers(customers, subscriptions) do
    Onestack.CustomerCombiner.combine_customers(customers, subscriptions)
  end

  @doc false
  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
