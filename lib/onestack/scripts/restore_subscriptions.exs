#!/usr/bin/env elixir

# Script to restore subscriptions for existing customers who lost their subscription data
# due to the table being dropped and recreated in migration 20250809150220_fix_selected_products_column_type.exs

Mix.install([
  {:ecto_sqlite3, "~> 0.12"},
  {:ecto, "~> 3.10"},
  {:jason, "~> 1.4"}
])

defmodule RestoreSubscriptions do
  require Logger

  @doc """
  Restores subscription records for teams that have products but no corresponding subscription.
  
  This script analyzes the teams table and creates appropriate subscription records
  for teams that have products but no active subscription.
  """
  def restore_all do
    Logger.info("Starting subscription restoration process...")
    
    # Get all teams with products but no active subscription
    teams_needing_subscriptions = get_teams_needing_subscriptions()
    
    Logger.info("Found #{length(teams_needing_subscriptions)} teams that need subscription restoration")
    
    Enum.each(teams_needing_subscriptions, fn team ->
      restore_subscription_for_team(team)
    end)
    
    Logger.info("Subscription restoration complete!")
  end

  defp get_teams_needing_subscriptions do
    # This would normally use Ecto queries, but for simplicity using raw SQL
    # You'll need to adapt this to your actual database setup
    
    # Query teams that have products but no corresponding active subscription
    query = """
    SELECT t.id, t.admin_email, t.products, t.members 
    FROM teams t
    LEFT JOIN subscriptions s ON s.customer_email = t.admin_email AND s.status = 'active'
    WHERE json_array_length(t.products) > 0 
    AND s.id IS NULL
    """
    
    # This is a placeholder - you'll need to execute this query against your database
    # and return the results as a list of maps
    []
  end

  defp restore_subscription_for_team(team) do
    Logger.info("Restoring subscription for team #{team[:id]} (admin: #{team[:admin_email]})")
    
    # Parse the products JSON array
    products = case Jason.decode(team[:products]) do
      {:ok, products_list} when is_list(products_list) -> products_list
      _ -> []
    end
    
    # Parse the members JSON array to determine plan type and user count
    members = case Jason.decode(team[:members]) do
      {:ok, members_list} when is_list(members_list) -> members_list
      _ -> [team[:admin_email]]
    end
    
    # Determine plan type based on number of members
    plan_type = if length(members) > 1, do: "team", else: "individual"
    num_users = length(members)
    
    # Create subscription record
    subscription_attrs = %{
      status: "active",
      stripe_subscription_id: nil, # Will be nil for restored subscriptions
      stripe_customer_id: nil,     # Will be nil for restored subscriptions  
      customer_email: team[:admin_email],
      plan_type: plan_type,
      num_users: num_users,
      selected_products: products,
      metadata: %{
        "restored_from_team" => true,
        "original_team_id" => team[:id],
        "restoration_date" => DateTime.utc_now() |> DateTime.to_iso8601()
      },
      user_id: get_user_id_by_email(team[:admin_email])
    }
    
    # Insert subscription (you'll need to adapt this to use your actual Repo)
    Logger.info("Creating subscription with #{length(products)} products for #{plan_type} plan")
    
    # Placeholder for actual insertion - replace with:
    # case Onestack.Subscriptions.create_subscription(subscription_attrs) do
    #   {:ok, subscription} -> 
    #     Logger.info("Successfully created subscription #{subscription.id}")
    #   {:error, changeset} -> 
    #     Logger.error("Failed to create subscription: #{inspect(changeset.errors)}")
    # end
  end

  defp get_user_id_by_email(email) do
    # Placeholder - replace with actual user lookup:
    # case Onestack.Accounts.get_user_by_email(email) do
    #   %{id: id} -> id
    #   nil -> nil
    # end
    nil
  end
end

# Usage:
# RestoreSubscriptions.restore_all()