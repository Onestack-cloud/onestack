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
end
