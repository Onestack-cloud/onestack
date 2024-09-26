defmodule Onestack.MatrixAccounts do
  @moduledoc """
  The MatrixAccounts context.
  """

  import Ecto.Query, warn: false
  alias Onestack.Repo

  alias Onestack.MatrixAccounts.MatrixUser

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%MatrixUser{}, ...]

  """
  def list_users do
    Repo.all(MatrixUser)
  end

  @doc """
  Gets a single matrix_user.

  Raises `Ecto.NoResultsError` if the Matrix user does not exist.

  ## Examples

      iex> get_matrix_user!(123)
      %MatrixUser{}

      iex> get_matrix_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_matrix_user!(id), do: Repo.get!(MatrixUser, id)

  def get_matrix_user_by_email!(email) do
    Repo.get_by!(MatrixUser, email: email)
  end

  def update_matrix_user_by_email(email, attrs) do
    email
    |> get_matrix_user_by_email!()
    |> MatrixUser.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a matrix_user.

  ## Examples

      iex> create_matrix_user(%{field: value})
      {:ok, %MatrixUser{}}

      iex> create_matrix_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_matrix_user(attrs \\ %{}) do
    %MatrixUser{}
    |> MatrixUser.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a matrix_user.

  ## Examples

      iex> update_matrix_user(matrix_user, %{field: new_value})
      {:ok, %MatrixUser{}}

      iex> update_matrix_user(matrix_user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_matrix_user(%MatrixUser{} = matrix_user, attrs) do
    matrix_user
    |> MatrixUser.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a matrix_user.

  ## Examples

      iex> delete_matrix_user(matrix_user)
      {:ok, %MatrixUser{}}

      iex> delete_matrix_user(matrix_user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_matrix_user(%MatrixUser{} = matrix_user) do
    Repo.delete(matrix_user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking matrix_user changes.

  ## Examples

      iex> change_matrix_user(matrix_user)
      %Ecto.Changeset{data: %MatrixUser{}}

  """
  def change_matrix_user(%MatrixUser{} = matrix_user, attrs \\ %{}) do
    MatrixUser.changeset(matrix_user, attrs)
  end
end
