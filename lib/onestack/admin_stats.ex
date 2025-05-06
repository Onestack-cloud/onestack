defmodule Onestack.Admin.Stats do
  @moduledoc """
  Context for fetching common statistics and metrics used across the application.
  """

  alias Onestack.{StripeCache, Teams, Accounts}

  @doc """
  Gets common stats for a user including team members and products.
  """
  def get_user_stats(user) when not is_nil(user) do
    %{
      team_members: get_team_members(user),
      subscribed_product_names: get_user_products(user),
      combined_customers: StripeCache.list_combined_customers(),
      upcoming_invoice: get_upcoming_invoice(user)
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
    combined_customers = StripeCache.list_combined_customers()

    stripe_customer =
      Enum.find(combined_customers, fn customer -> customer.email == user.email end)

    case Onestack.StripeCache.get_upcoming_invoice(stripe_customer.subscription_id) do
      nil ->
        {:error, "Subscription not found"}

      subscription ->
        subscription
    end
  end
end
