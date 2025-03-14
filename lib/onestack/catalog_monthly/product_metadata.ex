defmodule Onestack.CatalogMonthly.ProductMetadata do
  import Ecto.Query
  alias Onestack.Repo
  alias Onestack.CatalogMonthly.ComparisonProduct

  @doc """
  Gets product metadata for a given product name.
  Returns a map with :icon, :display_name, and :benefits, similar to Features.get_feature/1
  """
  def get_metadata(product_name) when is_binary(product_name) do
    query =
      from p in ComparisonProduct,
        where:
          fragment("LOWER(?)", p.onestack_product_name) == fragment("LOWER(?)", ^product_name),
        select: %{
          icon: p.icon_name,
          feature_description: p.feature_description,
          closed_source_user_price: p.closed_source_user_price,
          closed_source_currency: p.closed_source_currency
        }

    case Repo.one(query) do
      nil ->
        nil

      metadata ->
        metadata
        |> Map.put(:display_name, display_name(metadata.feature_description))
        |> Map.put(:benefits, get_benefits_for_product(product_name))
    end
  end

  @doc """
  Returns a list of benefits for a specific product.
  This could be extended to fetch from database in the future.
  """
  def get_benefits_for_product(product_name) do
    # This is a placeholder for product-specific benefits
    # In a real implementation, these would come from a database
    case product_name do
      "auth" ->
        [
          "Secure authentication for your users",
          "Multiple authentication methods",
          "User management and permissions"
        ]

      "payments" ->
        [
          "Accept payments through multiple providers",
          "Manage subscriptions and billing",
          "Detailed transaction reporting"
        ]

      "analytics" ->
        [
          "Real-time user analytics",
          "Custom dashboards and reports",
          "Behavior tracking and insights"
        ]

      "email" ->
        [
          "Transactional email delivery",
          "Email templates and customization",
          "Delivery tracking and analytics"
        ]

      "storage" ->
        [
          "Secure file storage and management",
          "Automatic backups and versioning",
          "Fast CDN delivery worldwide"
        ]

      "ai" ->
        [
          "Integrate AI capabilities into your app",
          "Natural language processing",
          "Image and content generation"
        ]

      _ ->
        [
          "Streamline your workflow",
          "Save time and resources",
          "Improve productivity"
        ]
    end
  end

  @doc """
  Gets the icon for a product by its name
  """
  def get_icon(product_name) when is_binary(product_name) do
    query =
      from p in ComparisonProduct,
        where: p.onestack_product_name == ^product_name,
        select: p.icon_name

    Repo.one(query)
  end

  @doc """
  Gets the display name (feature description) for a product
  """
  def get_display_name(product_name) when is_binary(product_name) do
    query =
      from p in ComparisonProduct,
        where: p.onestack_product_name == ^product_name,
        select: p.feature_description

    Repo.one(query)
  end

  @doc """
  Lists all products with their metadata
  """
  def all_products do
    query =
      from p in ComparisonProduct,
        select: %{
          onestack_product_name: p.onestack_product_name,
          icon: p.icon_name,
          closed_source_name: p.closed_source_name,
          feature_description: p.feature_description,
          closed_source_user_price: p.closed_source_user_price,
          closed_source_currency: p.closed_source_currency
        }

    Repo.all(query)
    |> Enum.map(fn product ->
      Map.put(product, :display_name, display_name(product.feature_description))
    end)
  end

  def display_name(feature_description) do
    String.replace(feature_description, "_", " ")
    |> String.capitalize()
  end
end
