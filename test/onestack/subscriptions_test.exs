defmodule Onestack.SubscriptionsTest do
  use Onestack.DataCase

  alias Onestack.Subscriptions

  describe "subscriptions" do
    alias Onestack.Subscriptions.Subscription

    import Onestack.SubscriptionsFixtures

    @invalid_attrs %{status: nil}

    test "list_subscriptions/0 returns all subscriptions" do
      subscription = subscription_fixture()
      assert Subscriptions.list_subscriptions() == [subscription]
    end

    test "get_subscription!/1 returns the subscription with given id" do
      subscription = subscription_fixture()
      assert Subscriptions.get_subscription!(subscription.id) == subscription
    end

    test "create_subscription/1 with valid data creates a subscription" do
      valid_attrs = %{status: "some status"}

      assert {:ok, %Subscription{} = subscription} =
               Subscriptions.create_subscription(valid_attrs)

      assert subscription.status == "some status"
    end

    test "create_subscription/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Subscriptions.create_subscription(@invalid_attrs)
    end

    test "update_subscription/2 with valid data updates the subscription" do
      subscription = subscription_fixture()
      update_attrs = %{status: "some updated status"}

      assert {:ok, %Subscription{} = subscription} =
               Subscriptions.update_subscription(subscription, update_attrs)

      assert subscription.status == "some updated status"
    end

    test "update_subscription/2 with invalid data returns error changeset" do
      subscription = subscription_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Subscriptions.update_subscription(subscription, @invalid_attrs)

      assert subscription == Subscriptions.get_subscription!(subscription.id)
    end

    test "delete_subscription/1 deletes the subscription" do
      subscription = subscription_fixture()
      assert {:ok, %Subscription{}} = Subscriptions.delete_subscription(subscription)
      assert_raise Ecto.NoResultsError, fn -> Subscriptions.get_subscription!(subscription.id) end
    end

    test "change_subscription/1 returns a subscription changeset" do
      subscription = subscription_fixture()
      assert %Ecto.Changeset{} = Subscriptions.change_subscription(subscription)
    end
  end

  describe "customers" do
    alias Onestack.Subscriptions.Customer

    import Onestack.SubscriptionsFixtures

    @invalid_attrs %{email: nil, customer_id: nil, products: nil}

    test "list_customers/0 returns all customers" do
      customer = customer_fixture()
      assert Subscriptions.list_customers() == [customer]
    end

    test "get_customer!/1 returns the customer with given id" do
      customer = customer_fixture()
      assert Subscriptions.get_customer!(customer.id) == customer
    end

    test "create_customer/1 with valid data creates a customer" do
      valid_attrs = %{
        email: "some email",
        customer_id: "some customer_id",
        products: ["option1", "option2"]
      }

      assert {:ok, %Customer{} = customer} = Subscriptions.create_customer(valid_attrs)
      assert customer.email == "some email"
      assert customer.customer_id == "some customer_id"
      assert customer.products == ["option1", "option2"]
    end

    test "create_customer/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Subscriptions.create_customer(@invalid_attrs)
    end

    test "update_customer/2 with valid data updates the customer" do
      customer = customer_fixture()

      update_attrs = %{
        email: "some updated email",
        customer_id: "some updated customer_id",
        products: ["option1"]
      }

      assert {:ok, %Customer{} = customer} = Subscriptions.update_customer(customer, update_attrs)
      assert customer.email == "some updated email"
      assert customer.customer_id == "some updated customer_id"
      assert customer.products == ["option1"]
    end

    test "update_customer/2 with invalid data returns error changeset" do
      customer = customer_fixture()
      assert {:error, %Ecto.Changeset{}} = Subscriptions.update_customer(customer, @invalid_attrs)
      assert customer == Subscriptions.get_customer!(customer.id)
    end

    test "delete_customer/1 deletes the customer" do
      customer = customer_fixture()
      assert {:ok, %Customer{}} = Subscriptions.delete_customer(customer)
      assert_raise Ecto.NoResultsError, fn -> Subscriptions.get_customer!(customer.id) end
    end

    test "change_customer/1 returns a customer changeset" do
      customer = customer_fixture()
      assert %Ecto.Changeset{} = Subscriptions.change_customer(customer)
    end
  end
end
