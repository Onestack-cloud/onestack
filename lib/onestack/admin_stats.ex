defmodule Onestack.Admin.Stats do
  @moduledoc """
  Context for fetching common statistics and metrics used across the application.
  """

  alias Onestack.{StripeCache, Teams}

  @doc """
  Gets common stats for a user including team members and products.
  """
  def get_user_stats(user) when not is_nil(user) do
    upcoming_invoice = case get_upcoming_invoice(user) do
      {:error, _reason} -> nil
      invoice -> invoice
    end
    
    %{
      team_members: get_team_members(user),
      subscribed_product_names: get_user_products(user),
      combined_customers: StripeCache.list_combined_customers(),
      upcoming_invoice: upcoming_invoice
    }
  end

  def get_user_stats(nil),
    do: %{
      team_members: [],
      subscribed_product_names: [],
      combined_customers: [],
      upcoming_invoice: []
    }

  defp get_team_members(user) do
    direct_members = Teams.list_team_members_by_admin(user)

    if direct_members == [] do
      # Check if user is member of any teams
      team =
        Enum.find(Teams.list_teams(), fn t ->
          user.email in t.members
        end)

      case team do
        nil -> []
        team -> team.members
      end
    else
      direct_members
    end
  end

  defp get_user_products(user) do
    team = Teams.get_team_by_admin(user)

    case team do
      nil -> []
      team -> team.products
    end
  end

  defp get_upcoming_invoice(user) do
    # First try to find subscription in our database
    case Onestack.Subscriptions.get_subscription_by_email(user.email) do
      nil ->
        # Fallback to StripeCache if not found in database
        get_upcoming_invoice_from_cache(user)
        
      subscription when subscription.status == "active" ->
        case Onestack.StripeCache.get_upcoming_invoice(subscription.stripe_subscription_id) do
          nil -> {:error, "Subscription not found"}
          invoice -> invoice
        end
        
      _subscription ->
        {:error, "No active subscription"}
    end
  end

  defp get_upcoming_invoice_from_cache(user) do
    combined_customers = StripeCache.list_combined_customers()

    stripe_customer =
      Enum.find(combined_customers, fn customer -> customer.email == user.email end)

    case stripe_customer do
      nil ->
        {:error, "Customer not found"}
      
      customer when is_nil(customer.subscription_id) ->
        {:error, "No active subscription"}
        
      customer ->
        case Onestack.StripeCache.get_upcoming_invoice(customer.subscription_id) do
          nil ->
            {:error, "Subscription not found"}

          subscription ->
            subscription
        end
    end
  end
end
