defmodule Onestack.SubscriptionsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Onestack.Subscriptions` context.
  """

  @doc """
  Generate a subscription.
  """
  def subscription_fixture(attrs \\ %{}) do
    {:ok, subscription} =
      attrs
      |> Enum.into(%{
        status: "some status"
      })
      |> Onestack.Subscriptions.create_subscription()

    subscription
  end

  @doc """
  Generate a unique customer customer_id.
  """
  def unique_customer_customer_id, do: "some customer_id#{System.unique_integer([:positive])}"

  @doc """
  Generate a unique customer email.
  """
  def unique_customer_email, do: "some email#{System.unique_integer([:positive])}"

  @doc """
  Generate a customer.
  """
  def customer_fixture(attrs \\ %{}) do
    {:ok, customer} =
      attrs
      |> Enum.into(%{
        customer_id: unique_customer_customer_id(),
        email: unique_customer_email(),
        products: ["option1", "option2"]
      })
      |> Onestack.Subscriptions.create_customer()

    customer
  end
end
