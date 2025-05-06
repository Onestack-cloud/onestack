defmodule Onestack.Repo.Migrations.CreateProductsCentral do
  use Ecto.Migration
  alias Onestack.CatalogMonthly.ComparisonProduct
  alias Onestack.Repo

  def change do
    create table(:products_central) do
      add :closed_source_name, :string
      add :onestack_product_name, :string
      add :closed_source_user_price, :decimal
      add :closed_source_currency, :string
      add :icon_name, :string
      add :feature_description, :string

      timestamps(type: :utc_datetime)
    end
  end

  def after_all do
    products = [
      %{
        onestack_product_name: "Kimai",
        closed_source_name: "toggl.com",
        closed_source_user_price: Decimal.new("10"),
        closed_source_currency: "USD",
        feature_description: "time_tracking",
        icon_name: "clock"
      },
      %{
        onestack_product_name: "Matrix",
        closed_source_name: "slack.com",
        closed_source_user_price: Decimal.new("8.75"),
        closed_source_currency: "USD",
        feature_description: "project_management",
        icon_name: "layout-grid"
      },
      %{
        onestack_product_name: "Chatwoot",
        closed_source_name: "intercom.com",
        closed_source_user_price: Decimal.new("15"),
        closed_source_currency: "USD",
        feature_description: "team_chat",
        icon_name: "message-circle"
      },
      %{
        onestack_product_name: "Penpot",
        closed_source_name: "figma.com",
        closed_source_user_price: Decimal.new("12"),
        closed_source_currency: "USD",
        feature_description: "design",
        icon_name: "shapes"
      },
      %{
        onestack_product_name: "Plane",
        closed_source_name: "linear.app",
        closed_source_user_price: Decimal.new("10"),
        closed_source_currency: "USD",
        feature_description: "task_management",
        icon_name: "square-check"
      },
      %{
        onestack_product_name: "Cal",
        closed_source_name: "calendly.com",
        closed_source_user_price: Decimal.new("12"),
        closed_source_currency: "USD",
        feature_description: "calendar",
        icon_name: "calendar"
      },
      %{
        onestack_product_name: "Formbricks",
        closed_source_name: "typeform.com",
        closed_source_user_price: Decimal.new("25"),
        closed_source_currency: "USD",
        feature_description: "form_builder",
        icon_name: "text-cursor-input"
      },
      %{
        onestack_product_name: "Documenso",
        closed_source_name: "docusign.com",
        closed_source_user_price: Decimal.new("10"),
        closed_source_currency: "USD",
        feature_description: "document_signing",
        icon_name: "signature"
      },
      %{
        onestack_product_name: "Castopod",
        closed_source_name: "buzzsprout.com",
        closed_source_user_price: Decimal.new("12"),
        closed_source_currency: "USD",
        feature_description: "podcast_hosting",
        icon_name: "mic"
      }
    ]

    Enum.each(products, fn product_attrs ->
      %ComparisonProduct{}
      |> ComparisonProduct.changeset(product_attrs)
      |> Repo.insert!()
    end)
  end
end
