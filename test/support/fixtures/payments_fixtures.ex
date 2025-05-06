defmodule Onestack.PaymentsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Onestack.Payments` context.
  """

  @doc """
  Generate a payment.
  """
  def payment_fixture(attrs \\ %{}) do
    {:ok, payment} =
      attrs
      |> Enum.into(%{
        amount: 42,
        name: "some name",
        payment_intent_id: "some payment_intent_id"
      })
      |> Onestack.Payments.create_payment()

    payment
  end
end
