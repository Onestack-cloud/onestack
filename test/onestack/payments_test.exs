defmodule Onestack.PaymentsTest do
  use Onestack.DataCase

  alias Onestack.Payments

  describe "payments" do
    alias Onestack.Payments.Payment

    import Onestack.PaymentsFixtures

    @invalid_attrs %{name: nil, amount: nil, payment_intent_id: nil}

    test "list_payments/0 returns all payments" do
      payment = payment_fixture()
      assert Payments.list_payments() == [payment]
    end

    test "get_payment!/1 returns the payment with given id" do
      payment = payment_fixture()
      assert Payments.get_payment!(payment.id) == payment
    end

    test "create_payment/1 with valid data creates a payment" do
      valid_attrs = %{name: "some name", amount: 42, payment_intent_id: "some payment_intent_id"}

      assert {:ok, %Payment{} = payment} = Payments.create_payment(valid_attrs)
      assert payment.name == "some name"
      assert payment.amount == 42
      assert payment.payment_intent_id == "some payment_intent_id"
    end

    test "create_payment/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Payments.create_payment(@invalid_attrs)
    end

    test "update_payment/2 with valid data updates the payment" do
      payment = payment_fixture()

      update_attrs = %{
        name: "some updated name",
        amount: 43,
        payment_intent_id: "some updated payment_intent_id"
      }

      assert {:ok, %Payment{} = payment} = Payments.update_payment(payment, update_attrs)
      assert payment.name == "some updated name"
      assert payment.amount == 43
      assert payment.payment_intent_id == "some updated payment_intent_id"
    end

    test "update_payment/2 with invalid data returns error changeset" do
      payment = payment_fixture()
      assert {:error, %Ecto.Changeset{}} = Payments.update_payment(payment, @invalid_attrs)
      assert payment == Payments.get_payment!(payment.id)
    end

    test "delete_payment/1 deletes the payment" do
      payment = payment_fixture()
      assert {:ok, %Payment{}} = Payments.delete_payment(payment)
      assert_raise Ecto.NoResultsError, fn -> Payments.get_payment!(payment.id) end
    end

    test "change_payment/1 returns a payment changeset" do
      payment = payment_fixture()
      assert %Ecto.Changeset{} = Payments.change_payment(payment)
    end
  end
end
