defmodule Onestack.Scripts.UpdateProductNames do
  alias Onestack.Teams
  require Logger
  alias OnestackWeb.SubscribeLive

  def run do
    teams = Teams.list_teams()
    stripe_products = Onestack.StripeCache.list_products()

    Enum.each(teams, fn team ->
      if team.products != [] do
        updated_products =
          team.products
          |> Enum.map(fn product ->
            if String.starts_with?(product, "prod_") do
              # Wrap single product in a list since get_product_names expects a list
              [updated_name] = SubscribeLive.get_product_names([product])
              updated_name
            else
              product
            end
          end)

        # Update the team with new product names
        Teams.update_team(team, %{products: updated_products})
      end
    end)
  end
end
