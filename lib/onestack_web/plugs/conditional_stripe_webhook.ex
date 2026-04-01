defmodule OnestackWeb.Plugs.ConditionalStripeWebhook do
  @moduledoc """
  A plug that delegates to Stripe.WebhookPlug only when Stripe is enabled.
  When Stripe is disabled, requests to the webhook path pass through untouched.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: Stripe.WebhookPlug.init(opts)

  @impl true
  def call(%Plug.Conn{request_path: "/webhooks/stripe"} = conn, opts) do
    if Onestack.stripe_enabled?() do
      Stripe.WebhookPlug.call(conn, opts)
    else
      conn
    end
  end

  def call(conn, _opts), do: conn
end
