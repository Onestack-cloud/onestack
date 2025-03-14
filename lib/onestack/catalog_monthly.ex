defmodule Onestack.CatalogMonthly do
  @moduledoc """
  The CatalogMonthly context.
  """

  import Ecto.Query, warn: false
  alias Onestack.Repo

  alias Onestack.CatalogMonthly.ComparisonProduct

  @doc """
  Returns the list of products.

  ## Examples

      iex> list_products()
      [%ComparisonProduct{}, ...]

  """
  def list_products do
    Repo.all(ComparisonProduct)
    |> Enum.map(fn product ->
      product
      |> Map.put(
        :display_name,
        Onestack.CatalogMonthly.ProductMetadata.display_name(product.feature_description)
      )
    end)
  end

  @doc """
  Gets a single product.

  Raises `Ecto.NoResultsError` if the Product does not exist.

  ## Examples

      iex> get_product!(123)
      %ComparisonProduct{}

      iex> get_product!(456)
      ** (Ecto.NoResultsError)

  """
  def get_product!(id), do: Repo.get!(ComparisonProduct, id)

  @doc """
  Creates a product.

  ## Examples

      iex> create_product(%{field: value})
      {:ok, %ComparisonProduct{}}

      iex> create_product(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_product(attrs \\ %{}) do
    %ComparisonProduct{}
    |> ComparisonProduct.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product.

  ## Examples

      iex> update_product(product, %{field: new_value})
      {:ok, %ComparisonProduct{}}

      iex> update_product(product, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_product(%ComparisonProduct{} = product, attrs) do
    product
    |> ComparisonProduct.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product.

  ## Examples

      iex> delete_product(product)
      {:ok, %ComparisonProduct{}}

      iex> delete_product(product)
      {:error, %Ecto.Changeset{}}

  """
  def delete_product(%ComparisonProduct{} = product) do
    Repo.delete(product)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking product changes.

  ## Examples

      iex> change_product(product)
      %Ecto.Changeset{data: %ComparisonProduct{}}

  """
  def change_product(%ComparisonProduct{} = product, attrs \\ %{}) do
    ComparisonProduct.changeset(product, attrs)
  end
  
  @doc """
  Gets the price for a product based on its index and plan type.
  Used for graduated pricing model with tiered pricing by product index.

  ## Examples

      iex> get_product_price(0, "team")
      10

      iex> get_product_price(3, "individual")
      2
  """
  def get_product_price(index, plan_type) do
    case plan_type do
      "individual" -> Enum.at([8, 6, 4, 2, 2, 2], index, 2)
      "team" -> Enum.at([10, 8, 6, 6, 6, 6], index, 6)
    end
  end
  
  @doc """
  Calculates the total price for a team subscription based on the number of products.
  Uses graduated pricing where each additional product is priced at its tier rate.

  ## Parameters
    - `product_count`: The number of products in the subscription
    - `plan_type`: Either "individual" or "team"

  ## Examples
      iex> calculate_subscription_price(3, "team")
      24 # (10 + 8 + 6 = 24)
  """
  def calculate_subscription_price(product_count, plan_type) do
    plan_type = plan_type || "team"
    
    # Calculate total by summing the prices for each product tier
    0..(product_count - 1)
    |> Enum.reduce(0, fn index, total ->
      total + get_product_price(index, plan_type)
    end)
  end
end
