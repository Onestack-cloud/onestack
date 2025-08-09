defmodule Onestack.Scripts.RestoreCustomerSubscriptions do
  @moduledoc """
  Script to restore subscriptions for existing customers who lost their subscription data
  due to the table being dropped and recreated in migration 20250809150220.
  
  Usage:
    # In IEx console:
    Onestack.Scripts.RestoreCustomerSubscriptions.restore_all()
    
    # Or restore for specific email:
    Onestack.Scripts.RestoreCustomerSubscriptions.restore_for_email("user@example.com")
  """
  
  import Ecto.Query
  alias Onestack.{Repo, Teams, Subscriptions, Accounts}
  require Logger

  def restore_all do
    Logger.info("🔄 Starting subscription restoration process...")
    
    teams_needing_subscriptions = get_teams_needing_subscriptions()
    
    Logger.info("📊 Found #{length(teams_needing_subscriptions)} teams that need subscription restoration")
    
    results = Enum.map(teams_needing_subscriptions, fn team ->
      restore_subscription_for_team(team)
    end)
    
    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    
    Logger.info("✅ Subscription restoration complete! Success: #{successful}, Failed: #{failed}")
    
    {:ok, %{successful: successful, failed: failed, results: results}}
  end

  def restore_for_email(email) do
    Logger.info("🔄 Restoring subscription for #{email}")
    
    user = Accounts.get_user_by_email(email)
    case user && Teams.get_team_by_admin(user) do
      nil -> 
        Logger.error("❌ No team found for admin email: #{email}")
        {:error, :no_team_found}
      
      team ->
        restore_subscription_for_team(team)
    end
  end

  defp get_teams_needing_subscriptions do
    # Get all teams that have products but no corresponding active subscription
    from(t in Onestack.Teams.Team,
      left_join: s in Onestack.Subscriptions.Subscription,
      on: s.customer_email == t.admin_email and s.status == "active",
      where: fragment("json_array_length(?)", t.products) > 0,
      where: is_nil(s.id),
      select: t
    )
    |> Repo.all()
  end

  defp restore_subscription_for_team(team) do
    Logger.info("🏗️  Restoring subscription for team #{team.id} (admin: #{team.admin_email})")
    
    # Determine plan type based on number of members
    num_members = length(team.members)
    plan_type = if num_members > 1, do: "team", else: "individual"
    
    # Get user ID for the admin
    user = Accounts.get_user_by_email(team.admin_email)
    user_id = if user, do: user.id, else: nil
    
    # Create subscription attributes
    subscription_attrs = %{
      status: "active",
      stripe_subscription_id: nil, # Will be nil for restored subscriptions
      stripe_customer_id: nil,     # Will be nil for restored subscriptions  
      customer_email: team.admin_email,
      plan_type: plan_type,
      num_users: num_members,
      selected_products: team.products,
      metadata: %{
        "restored_from_team" => true,
        "original_team_id" => team.id,
        "restoration_date" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "note" => "Restored after subscription table recreation on 2025-08-09"
      },
      user_id: user_id
    }
    
    Logger.info("📝 Creating subscription: #{plan_type} plan, #{num_members} users, #{length(team.products)} products")
    
    case Subscriptions.create_subscription(subscription_attrs) do
      {:ok, subscription} -> 
        Logger.info("✅ Successfully created subscription #{subscription.id} for #{team.admin_email}")
        {:ok, subscription}
        
      {:error, changeset} -> 
        Logger.error("❌ Failed to create subscription for #{team.admin_email}: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def preview_restoration do
    """
    Preview of teams that would have subscriptions restored:
    """
    |> IO.puts()
    
    teams = get_teams_needing_subscriptions()
    
    Enum.each(teams, fn team ->
      num_members = length(team.members)
      plan_type = if num_members > 1, do: "team", else: "individual"
      
      IO.puts("📧 #{team.admin_email}")
      IO.puts("   👥 Members: #{num_members} (#{plan_type} plan)")  
      IO.puts("   🔧 Products: #{inspect(team.products)}")
      IO.puts("")
    end)
    
    IO.puts("Total teams to restore: #{length(teams)}")
  end
end