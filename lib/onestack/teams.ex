defmodule Onestack.Teams do
  @moduledoc """
  The Teams context.
  """

  import Ecto.Query, warn: false
  alias Onestack.Repo

  alias Onestack.Teams.Team

  @doc """
  Returns the list of teams.

  ## Examples

      iex> list_teams()
      [%Team{}, ...]

  """
  def list_teams do
    Repo.all(Team)
  end

  @doc """
  Gets a single team.

  Raises `Ecto.NoResultsError` if the Team does not exist.

  ## Examples

      iex> get_team!(123)
      %Team{}

      iex> get_team!(456)
      ** (Ecto.NoResultsError)

  """
  def get_team!(id), do: Repo.get!(Team, id)

  @doc """
  Creates a team.

  ## Examples

      iex> create_team(%{field: value})
      {:ok, %Team{}}

      iex> create_team(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_team(attrs \\ %{}) do
    %Team{}
    |> Team.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a team.

  ## Examples

      iex> update_team(team, %{field: new_value})
      {:ok, %Team{}}

      iex> update_team(team, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_team(%Team{} = team, attrs) do
    team
    |> Team.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a team.

  ## Examples

      iex> delete_team(team)
      {:ok, %Team{}}

      iex> delete_team(team)
      {:error, %Ecto.Changeset{}}

  """
  def delete_team(%Team{} = team) do
    Repo.delete(team)
  end

  @doc """
  Adds a team member to the admin user's team.

  ## Examples

      iex> add_team_member(admin_user, "new_member@example.com", ["product1", "product2"])
      {:ok, %Team{}}

      iex> add_team_member(admin_user, "invalid_email", ["product1"])
      {:error, %Ecto.Changeset{}}

  """
  def add_team_member(admin_user, email, products) do
    team = get_or_create_team(admin_user)

    new_members = [email | team.members]
    new_products = Enum.uniq(team.products ++ products)

    team
    |> Team.changeset(%{members: new_members, products: new_products})
    |> Repo.update()
  end

  @doc """
  Removes a team member from the admin user's team.

  ## Examples

      iex> remove_team_member(admin_user, "member@example.com")
      {:ok, %Team{}}

      iex> remove_team_member(admin_user, "nonexistent@example.com")
      {:error, :not_found}

  """
  def remove_team_member(admin_user, email) do
    case get_team_by_admin(admin_user) do
      nil ->
        {:error, :not_found}

      team ->
        new_members = Enum.reject(team.members, &(&1 == email))

        if length(new_members) == length(team.members) do
          {:error, :not_found}
        else
          team
          |> Team.changeset(%{members: new_members})
          |> Repo.update()
        end
    end
  end

  @doc """
  Lists all team members for a given user's team.

  ## Examples

      iex> list_team_members(user)
      ["member1@example.com", "member2@example.com"]

  """
  def list_team_members(user) do
    case get_team_by_admin(user) do
      nil -> []
      team -> team.members
    end
  end

  # Private helper functions

  defp get_or_create_team(user) do
    case get_team_by_admin(user) do
      nil -> create_team(%{members: [user.email], products: [], admin_email: user.email})
      team -> team
    end
  end

  defp get_team_by_admin(user) do
    Repo.get_by(Team, admin_email: user.email)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking team changes.

  ## Examples

      iex> change_team(team)
      %Ecto.Changeset{data: %Team{}}

  """
  def change_team(%Team{} = team, attrs \\ %{}) do
    Team.changeset(team, attrs)
  end
end
