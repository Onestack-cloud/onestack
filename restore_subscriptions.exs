#!/usr/bin/env elixir

# Simple script to restore subscriptions for existing customers
# Usage: elixir restore_subscriptions.exs

Mix.install([])

# Add the project path to the load path
Code.append_path("lib")

# Load the required application modules
Application.ensure_all_started(:logger)
Application.ensure_all_started(:ecto)
Application.ensure_all_started(:ecto_sqlite3)

# Import the script module
Code.require_file("lib/onestack/scripts/restore_customer_subscriptions.ex")

# Run the preview first to see what would be restored
IO.puts("📋 Preview of teams that need subscription restoration:")
IO.puts("==================================================")

Onestack.Scripts.RestoreCustomerSubscriptions.preview_restoration()

IO.puts("\n⚠️  Do you want to proceed with restoration? (y/N)")
response = IO.gets("") |> String.trim() |> String.downcase()

if response == "y" do
  IO.puts("🚀 Starting restoration process...")
  
  case Onestack.Scripts.RestoreCustomerSubscriptions.restore_all() do
    {:ok, %{successful: successful, failed: failed}} ->
      IO.puts("✅ Restoration complete!")
      IO.puts("   - Successfully restored: #{successful}")
      IO.puts("   - Failed: #{failed}")
      
    {:error, reason} ->
      IO.puts("❌ Restoration failed: #{inspect(reason)}")
  end
else
  IO.puts("❌ Restoration cancelled.")
end