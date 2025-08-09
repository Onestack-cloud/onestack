defmodule OnestackWeb.StripeHandler do
  @behaviour Stripe.WebhookHandler

  alias Onestack.{Payments, Subscriptions}

  @impl true
  def handle_event(%Stripe.Event{type: "checkout.session.completed"} = event) do
    IO.inspect(event, label: "STRIPE CHECKOUT SESSION COMPLETED")
    
    # Handle subscription creation from checkout
    session = event.data.object
    
    mode = session[:mode] || session["mode"]
    if mode == "subscription" do
      # This is a subscription checkout
      handle_subscription_creation(session)
    else
      # Handle one-time payments
      %{amount_total: amount, payment_intent: payment_intent} = session
      %{"name" => name} = session.metadata

      Payments.create_payment(%{
        amount: amount,
        payment_intent_id: payment_intent,
        name: name
      })
    end

    {:ok, "success"}
  end

  @impl true
  def handle_event(%Stripe.Event{type: "customer.subscription.created"} = event) do
    IO.inspect(event, label: "STRIPE SUBSCRIPTION CREATED")
    subscription = event.data.object
    handle_subscription_creation_from_webhook(subscription)
    {:ok, "success"}
  end
  
  @impl true 
  def handle_event(%Stripe.Event{type: "customer.subscription.updated"} = event) do
    IO.inspect(event, label: "STRIPE SUBSCRIPTION UPDATED")
    subscription = event.data.object
    
    # Update subscription status if it changed
    subscription_id = subscription[:id] || subscription["id"]
    status = subscription[:status] || subscription["status"]
    Subscriptions.update_subscription_status(subscription_id, status)
    {:ok, "success"}
  end

  @impl true
  def handle_event(%Stripe.Event{type: "customer.subscription.deleted"} = event) do
    IO.inspect(event, label: "STRIPE SUBSCRIPTION DELETED")
    subscription = event.data.object
    
    # Mark subscription as cancelled/deleted
    subscription_id = subscription[:id] || subscription["id"]
    Subscriptions.update_subscription_status(subscription_id, "cancelled")
    {:ok, "success"}
  end

  # Return HTTP 200 for unhandled events
  @impl true
  def handle_event(_event), do: :ok

  # Handle subscription creation from checkout session
  defp handle_subscription_creation(session) do
    session_id = session[:id] || session["id"]
    IO.puts("Processing subscription from checkout session: #{session_id}")
    
    # Extract subscription info from session
    customer_details = session[:customer_details] || session["customer_details"]
    customer_email = customer_details[:email] || customer_details["email"]
    subscription_id = session[:subscription] || session["subscription"]
    
    # Get the customer from Stripe
    customer_id = session[:customer] || session["customer"]
    case Stripe.Customer.retrieve(customer_id) do
      {:ok, customer} ->
        # Create or update subscription in your database
        metadata = session[:metadata] || session["metadata"] || %{}
        create_or_update_subscription(customer, subscription_id, metadata)
        
      {:error, error} ->
        IO.inspect(error, label: "Error retrieving customer")
    end
  end

  # Handle subscription creation from webhook  
  defp handle_subscription_creation_from_webhook(subscription) do
    subscription_id = subscription["id"] || subscription[:id]
    customer_id = subscription["customer"] || subscription[:customer]
    
    IO.puts("Processing subscription from webhook: #{subscription_id}")
    
    case Stripe.Customer.retrieve(customer_id) do
      {:ok, customer} ->
        create_or_update_subscription(customer, subscription_id, %{})
        
      {:error, error} ->
        IO.inspect(error, label: "Error retrieving customer")
    end
  end

  # Create or update subscription in database
  defp create_or_update_subscription(customer, subscription_id, metadata) do
    IO.puts("Creating subscription:")
    IO.puts("  Customer: #{customer.email}")
    IO.puts("  Subscription ID: #{subscription_id}")
    IO.puts("  Metadata: #{inspect(metadata)}")
    
    case Subscriptions.create_subscription_from_stripe(customer, subscription_id, metadata) do
      {:ok, subscription} ->
        IO.puts("✅ Successfully created subscription: #{subscription.id}")
        subscription
        
      {:error, changeset} ->
        IO.inspect(changeset, label: "❌ Failed to create subscription")
        nil
    end
  end
end
