defmodule Onestack.Subscriptions do
  @moduledoc """
  The Subscriptions context.
  """

  import Ecto.Query, warn: false
  alias Onestack.Repo

  alias Onestack.Subscriptions.Subscription

  @doc """
  Returns the list of subscriptions.

  ## Examples

      iex> list_subscriptions()
      [%Subscription{}, ...]

  """
  def list_subscriptions do
    Repo.all(Subscription)
  end

  @doc """
  Gets a single subscription.

  Raises `Ecto.NoResultsError` if the Subscription does not exist.

  ## Examples

      iex> get_subscription!(123)
      %Subscription{}

      iex> get_subscription!(456)
      ** (Ecto.NoResultsError)

  """
  def get_subscription!(id), do: Repo.get!(Subscription, id)

  @doc """
  Creates a subscription.

  ## Examples

      iex> create_subscription(%{field: value})
      {:ok, %Subscription{}}

      iex> create_subscription(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_subscription(attrs \\ %{}) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a subscription.

  ## Examples

      iex> update_subscription(subscription, %{field: new_value})
      {:ok, %Subscription{}}

      iex> update_subscription(subscription, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_subscription(%Subscription{} = subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a subscription.

  ## Examples

      iex> delete_subscription(subscription)
      {:ok, %Subscription{}}

      iex> delete_subscription(subscription)
      {:error, %Ecto.Changeset{}}

  """
  def delete_subscription(%Subscription{} = subscription) do
    Repo.delete(subscription)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking subscription changes.

  ## Examples

      iex> change_subscription(subscription)
      %Ecto.Changeset{data: %Subscription{}}

  """
  def change_subscription(%Subscription{} = subscription, attrs \\ %{}) do
    Subscription.changeset(subscription, attrs)
  end

  alias Onestack.Subscriptions.Customer

  @doc """
  Returns the list of customers.

  ## Examples

      iex> list_customers()
      [%Customer{}, ...]

  """
  def list_customers do
    Repo.all(Customer)
  end

  @doc """
  Gets a single customer.

  Raises `Ecto.NoResultsError` if the Customer does not exist.

  ## Examples

      iex> get_customer!(123)
      %Customer{}

      iex> get_customer!(456)
      ** (Ecto.NoResultsError)

  """
  def get_customer!(id), do: Repo.get!(Customer, id)

  @doc """
  Creates a customer.

  ## Examples

      iex> create_customer(%{field: value})
      {:ok, %Customer{}}

      iex> create_customer(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_customer(attrs \\ %{}) do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a customer.

  ## Examples

      iex> update_customer(customer, %{field: new_value})
      {:ok, %Customer{}}

      iex> update_customer(customer, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a customer.

  ## Examples

      iex> delete_customer(customer)
      {:ok, %Customer{}}

      iex> delete_customer(customer)
      {:error, %Ecto.Changeset{}}

  """
  def delete_customer(%Customer{} = customer) do
    Repo.delete(customer)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking customer changes.

  ## Examples

      iex> change_customer(customer)
      %Ecto.Changeset{data: %Customer{}}

  """
  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end

  # Helper functions for Stripe webhook integration

  @doc """
  Creates a subscription from Stripe data.
  """
  def create_subscription_from_stripe(stripe_customer, stripe_subscription_id, metadata) do
    # Extract data from metadata
    plan_type = Map.get(metadata, "plan_type", "individual")
    num_users = case Map.get(metadata, "num_users") do
      nil -> 1
      num when is_binary(num) -> String.to_integer(num)
      num when is_integer(num) -> num
    end
    
    selected_products = case Map.get(metadata, "selected_products") do
      nil -> []
      products_json when is_binary(products_json) -> 
        case Jason.decode(products_json) do
          {:ok, products} when is_list(products) -> products
          _ -> []
        end
      products when is_list(products) -> products
    end

    # Try to find associated user
    user = Onestack.Accounts.get_user_by_email(stripe_customer.email)
    user_id = if user, do: user.id, else: nil

    attrs = %{
      status: "active",
      stripe_subscription_id: stripe_subscription_id,
      stripe_customer_id: stripe_customer.id,
      customer_email: stripe_customer.email,
      plan_type: plan_type,
      num_users: num_users,
      selected_products: selected_products,
      metadata: metadata,
      user_id: user_id
    }

    create_subscription(attrs)
  end

  @doc """
  Finds a subscription by Stripe subscription ID.
  """
  def get_subscription_by_stripe_id(stripe_subscription_id) do
    Repo.get_by(Subscription, stripe_subscription_id: stripe_subscription_id)
  end

  @doc """
  Finds a subscription by customer email.
  Returns the most recent active subscription, or nil if none found.
  """
  def get_subscription_by_email(email) do
    from(s in Subscription,
      where: s.customer_email == ^email,
      where: s.status == "active",
      order_by: [desc: s.updated_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Updates subscription status.
  """
  def update_subscription_status(stripe_subscription_id, status) do
    case get_subscription_by_stripe_id(stripe_subscription_id) do
      nil -> {:error, :not_found}
      subscription -> update_subscription(subscription, %{status: status})
    end
  end
end
