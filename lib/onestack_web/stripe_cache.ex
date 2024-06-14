defmodule Onestack.StripeCache do
  @moduledoc """
  StripeCache GenServer for managing Stripe prices and tax rates.
  """
  use GenServer
  require Logger

  alias Stripe.{Price, TaxRate, Product}
  defstruct [:tax_rates, :prices, :products]

  @refresh_interval :timer.minutes(60)

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

  # Server callbacks

  @doc false
  def init(_state) do
    with {:ok, %{data: prices}} <- Price.list(%{active: true}),
         {:ok, %{data: tax_rates}} <- TaxRate.list(%{active: true}),
         {:ok, %{data: products}} <- Product.list(%{active: true}) do
      schedule_refresh()
      {:ok, %__MODULE__{prices: prices, tax_rates: tax_rates, products: products}}
    else
      {:error, %Stripe.Error{message: message, code: code}} ->
        raise "Failed to initialise StripeCache: #{code} (#{message}). Ensure you have set up the Stripe Secret environment variable."
    end
  end

  @doc false
  def handle_info(:refresh, state) do
    schedule_refresh()

    with {:ok, %{data: prices}} <- Price.list(%{active: true}),
         {:ok, %{data: tax_rates}} <- TaxRate.list(%{active: true}),
         {:ok, %{data: products}} <- Product.list(%{active: true}) do
      {:noreply, %__MODULE__{prices: prices, tax_rates: tax_rates, products: products}}
    else
      {:error, reason} ->
        Logger.warn("Failed to refresh StripeCache: #{reason}. Using old state")
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
  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
