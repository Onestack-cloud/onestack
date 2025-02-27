defmodule Onestack.CatalogMonthly.ProductMetadata do
  import Ecto.Query
  alias Onestack.Repo
  alias Onestack.CatalogMonthly.ComparisonProduct

  @doc """
  Gets product metadata for a given product name.
  Returns a map with :icon and :display_name, similar to Features.get_feature/1
  """
  def get_metadata(product_name) when is_binary(product_name) do
    query =
      from p in ComparisonProduct,
        where: p.onestack_product_name == ^product_name,
        select: %{
          icon: p.icon_name,
          feature_description: p.feature_description,
          closed_source_user_price: p.closed_source_user_price,
          closed_source_currency: p.closed_source_currency
        }

    case Repo.one(query) do
      nil -> nil
      metadata -> Map.put(metadata, :display_name, display_name(metadata.feature_description))
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
