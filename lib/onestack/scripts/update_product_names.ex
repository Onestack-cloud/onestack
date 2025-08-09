defmodule Onestack.Scripts.UpdateProductNames do
  alias Onestack.Teams
  require Logger

  def run do
    teams = Teams.list_teams()
    
    Enum.each(teams, fn team ->
      if team.products != [] do
        updated_products =
          team.products
          |> Enum.map(fn product ->
            if String.starts_with?(product, "prod_") do
              # Convert Stripe product ID to readable name
              # This would need to be implemented with actual product name mapping
              Logger.info("Would update product: #{product}")
              product
            else
              product
            end
          end)

        # Commented out until proper mapping is implemented
        # Teams.update_team(team, %{products: updated_products})
      end
    end)
  end
end
