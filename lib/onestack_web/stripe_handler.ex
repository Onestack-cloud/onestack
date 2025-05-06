defmodule OnestackWeb.StripeHandler do
  @behaviour Stripe.WebhookHandler

  alias Onestack.Payments

  @impl true
  def handle_event(%Stripe.Event{type: "checkout.session.completed"} = event) do
    # The logic you want to execute on a successful payment goes here
    # For testing purposes, we will just output the result
    IO.inspect(event, label: "STRIPE EVENT")
    %{amount_total: amount, payment_intent: payment_intent} = event.data.object
    %{"name" => name} = event.data.object.metadata

    Payments.create_payment(%{
      amount: amount,
      payment_intent_id: payment_intent,
      name: name
    })

    {:ok, "success"}
  end

  # Return HTTP 200 for unhandled events
  @impl true
  def handle_event(_event), do: :ok
end
