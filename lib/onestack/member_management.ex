defmodule Onestack.MemberManagement do
  @moduledoc """
  The MemberManagement context.
  """

  import Ecto.Query, warn: false
  alias Onestack.Repo

  alias Onestack.MemberManagement.MemberCredentials

  @doc """
  Returns the list of member_credentials.

  ## Examples

      iex> list_member_credentials()
      [%MemberCredentials{}, ...]

  """
  def list_member_credentials do
    Repo.all(MemberCredentials)
  end

  @doc """
  Gets a single member_credentials.

  Raises `Ecto.NoResultsError` if the Member credentials does not exist.

  ## Examples

      iex> get_member_credentials!(123)
      %MemberCredentials{}

      iex> get_member_credentials!(456)
      ** (Ecto.NoResultsError)

  """
  def get_member_credentials!(id), do: Repo.get!(MemberCredentials, id)

  @doc """
  Creates a member_credentials.

  ## Examples

      iex> create_member_credentials(%{field: value})
      {:ok, %MemberCredentials{}}

      iex> create_member_credentials(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_member_credentials(attrs \\ %{}) do
    %MemberCredentials{}
    |> MemberCredentials.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a member_credentials.

  ## Examples

      iex> update_member_credentials(member_credentials, %{field: new_value})
      {:ok, %MemberCredentials{}}

      iex> update_member_credentials(member_credentials, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_member_credentials(%MemberCredentials{} = member_credentials, attrs) do
    member_credentials
    |> MemberCredentials.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a member_credentials.

  ## Examples

      iex> delete_member_credentials(member_credentials)
      {:ok, %MemberCredentials{}}

      iex> delete_member_credentials(member_credentials)
      {:error, %Ecto.Changeset{}}

  """
  def delete_member_credentials(%MemberCredentials{} = member_credentials) do
    Repo.delete(member_credentials)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking member_credentials changes.

  ## Examples

      iex> change_member_credentials(member_credentials)
      %Ecto.Changeset{data: %MemberCredentials{}}

  """
  def change_member_credentials(%MemberCredentials{} = member_credentials, attrs \\ %{}) do
    MemberCredentials.changeset(member_credentials, attrs)
  end
end
