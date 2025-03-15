defmodule Onestack.Scripts.SyncStripeAdmins do
  alias Onestack.Teams
  alias Onestack.Accounts
  require Logger

  def run do
    # Get all Stripe customers with active subscriptions
    stripe_customers = list_stripe_customers_with_subscriptions()

    Enum.each(stripe_customers, fn customer ->
      handle_customer(customer)
    end)
  end

  defp handle_customer(%Stripe.Customer{} = customer) do
    case customer.email do
      nil ->
        Logger.warning("Customer #{customer.id} has no email address")

      email ->
        # Check if team exists with this email
        case Teams.get_team_by_admin(%{email: email}) do
          nil -> create_team_with_user(email)
          team -> update_team_products(team, customer)
        end
    end
  end

  defp create_team_with_user(email) do
    team_params = %{
      admin_email: email,
      members: [email],
      products: get_subscription_products(email)
    }

    case Teams.create_team(team_params) do
      {:ok, team} ->
        Logger.info("Created team #{team.id} for #{email}")

      {:error, changeset} ->
        Logger.error("Failed to create team for #{email}: #{inspect(changeset.errors)}")
    end
  end

  defp update_team_products(team, customer) do
    # Pass the email string instead
    products = get_subscription_products(customer.email)

    case Teams.update_team(team, %{products: products}) do
      {:ok, team} ->
        Logger.info("Updated products for team #{team.id}")

      {:error, changeset} ->
        Logger.error("Failed to update team #{team.id}: #{inspect(changeset.errors)}")
    end
  end

  def list_stripe_customers_with_subscriptions do
    # Get all active subscriptions
    {:ok, %{data: subscriptions}} =
      Stripe.Subscription.list(%{
        # status: "active",
        expand: ["data.customer"],
        limit: 9999
      })

    # Extract customers with their latest subscription
    subscriptions
    |> Enum.sort_by(& &1.created, :desc)
    |> Enum.map(& &1.customer)
  end

  def get_subscription_products(email) do
    # Get customer by email
    {:ok, %{data: customers}} =
      Stripe.Customer.list(%{
        email: email,
        # Get more customers to sort through
        limit: 9999
      })
      |> case do
        {:ok, %{data: customers}} = _response ->
          {:ok, %{data: Enum.sort_by(customers, & &1.created, :desc)}}

        error ->
          error
      end

    case customers do
      [customer | _] ->
        # Get all active subscriptions for the customer
        {:ok, %{data: all_subscriptions}} =
          Stripe.Subscription.list(%{
            customer: customer.id
          })

        subscriptions =
          Enum.filter(all_subscriptions, fn subscription ->
            subscription.status in ["active", "trialing"]
          end)

        # Extract product IDs from subscriptions
        subscriptions
        |> Enum.flat_map(fn subscription ->
          subscription.items.data
          |> Enum.map(& &1.price.product)
        end)
        |> Enum.uniq()
        |> OnestackWeb.SubscribeLive.get_product_names()

      [] ->
        []
    end
  end
end
