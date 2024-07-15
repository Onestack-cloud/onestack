defmodule Onestack.StripeCache do
  @moduledoc """
  StripeCache GenServer for managing Stripe prices and tax rates.
  """
  use GenServer
  require Logger

  alias Stripe.{Price, TaxRate, Product, Subscription, Customer}
  defstruct [:tax_rates, :prices, :products, :customers, :subscriptions, :combined_customers]

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
    GenServer.cast(__MODULE__, {:update_subscription, subscription_id})
  end

  # Server callbacks

  @doc false
  def init(_state) do
    with {:ok, %{data: prices}} <- Price.list(%{active: true}),
         {:ok, %{data: tax_rates}} <- TaxRate.list(%{active: true}),
         {:ok, %{data: products}} <- Product.list(%{active: true}),
         {:ok, %{data: customers}} <- Customer.list(),
         {:ok, %{data: subscriptions}} <- Subscription.list(),
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
         combined_customers: combined_customers
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
         {:ok, %{data: customers}} <- Customer.list(),
         {:ok, %{data: subscriptions}} <- Subscription.list(),
         combined_customers =
           Onestack.CustomerCombiner.combine_customers(customers, subscriptions) do
      {:noreply,
       %__MODULE__{
         prices: prices,
         tax_rates: tax_rates,
         products: products,
         customers: customers,
         subscriptions: subscriptions,
         combined_customers: combined_customers
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

  @doc false
  def handle_call(
        :list_combined_customers,
        _from,
        %{combined_customers: combined_customers} = state
      ) do
    {:reply, combined_customers, state}
  end

  def handle_cast({:update_subscription, subscription_id}, state) do
    with {:ok, updated_subscription} <- Stripe.Subscription.retrieve(subscription_id),
         {:ok, %{data: customers}} <- Stripe.Customer.list(),
         {:ok, %{data: subscriptions}} <- Stripe.Subscription.list() do
      # Update the subscriptions list
      updated_subscriptions =
        Enum.map(state.subscriptions, fn sub ->
          if sub.id == subscription_id, do: updated_subscription, else: sub
        end)

      # Recalculate combined customers
      combined_customers =
        Onestack.CustomerCombiner.combine_customers(customers, updated_subscriptions)

      {:noreply,
       %{
         state
         | subscriptions: updated_subscriptions,
           customers: customers,
           combined_customers: combined_customers
       }}
    else
      {:error, reason} ->
        Logger.warning(
          "Failed to update StripeCache for subscription #{subscription_id}: #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  @doc false
  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
