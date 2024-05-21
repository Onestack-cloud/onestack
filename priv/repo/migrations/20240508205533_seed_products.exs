defmodule Onestack.Repo.Migrations.SeedProducts do
  use Ecto.Migration

  alias Onestack.Repo
  alias Onestack.CatalogMonthly.Product

  def change do
    products = [
      %{
        category: "Notes",
        closed_source_name: "notion.so",
        open_source_name: "affine.pro",
        closed_source_user_price: Decimal.new("10"),
        open_source_fixed_price: Decimal.new("10"),
        closed_source_currency: "USD",
        open_source_currency: "AUD"
      },
      %{
        category: "Project Management",
        closed_source_name: "linear.app",
        open_source_name: "plane.so",
        closed_source_user_price: Decimal.new("10"),
        open_source_fixed_price: Decimal.new("10"),
        closed_source_currency: "USD",
        open_source_currency: "AUD"
      },
      %{
        category: "Project Management",
        closed_source_name: "jira.com",
        open_source_name: "plane.so",
        closed_source_user_price: Decimal.new("7.16"),
        open_source_fixed_price: Decimal.new("10"),
        closed_source_currency: "USD",
        open_source_currency: "AUD"
      },
      %{
        category: "Internal Communication",
        closed_source_name: "slack.com",
        open_source_name: "zulip.com",
        closed_source_user_price: Decimal.new("8.75"),
        open_source_fixed_price: Decimal.new("10"),
        closed_source_currency: "USD",
        open_source_currency: "AUD"
      },
      %{
        category: "Scheduling",
        closed_source_name: "calendly.com",
        open_source_name: "cal.com",
        closed_source_user_price: Decimal.new("12"),
        open_source_fixed_price: Decimal.new("10"),
        closed_source_currency: "USD",
        open_source_currency: "AUD"
      },
      %{
        category: "Podcast Hosting",
        closed_source_name: "buzzsprout.com",
        open_source_name: "castopod.org",
        closed_source_user_price: Decimal.new("12"),
        open_source_fixed_price: Decimal.new("10"),
        closed_source_currency: "USD",
        open_source_currency: "AUD"
      }
    ]

    Enum.each(products, fn product_attrs ->
      %Product{}
      |> Product.changeset(product_attrs)
      |> Repo.insert!()
    end)
  end
end
