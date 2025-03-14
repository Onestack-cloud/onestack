defmodule Onestack.Teams do
  @moduledoc """
  The Teams context.
  """

  import Ecto.Query, warn: false
  alias Onestack.Repo

  alias Onestack.Teams.{Team, Invitation}

  # Invitation-related functions

  @doc """
  Creates a new team invitation.
  """
  def create_invitation(attrs) do
    %Invitation{}
    |> Invitation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a pending invitation for the given email address.
  Only returns invitations that:
  - Haven't been accepted
  - Haven't expired
  - Match the email exactly
  """
  def get_pending_invitation_by_id(invitation_id) when is_binary(invitation_id) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

    Invitation
    |> where([i], i.invitation_id == ^invitation_id)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^now)
    |> order_by([i], desc: i.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  # Add a clause to handle nil invitation_id
  def get_pending_invitation_by_id(nil), do: nil

  def get_pending_invitation_by_email(email) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)

    Invitation
    |> where([i], i.recipient_email == ^email)
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^now)
    |> order_by([i], desc: i.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Accepts an invitation and adds the user to the team.
  """
  def accept_invitation(%Invitation{} = invitation) do
    Repo.transaction(fn ->
      # Mark invitation as accepted
      invitation
      |> Invitation.changeset(%{
        accepted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)
      })
      |> Repo.update!()

      invitation
    end)
  end

  @doc """
  Lists all pending invitations for a team.
  Useful for showing pending invitations in the UI.
  """
  def list_pending_invitations() do
    now = DateTime.utc_now()

    Invitation
    |> where([i], is_nil(i.accepted_at))
    |> where([i], i.expires_at > ^now)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Deletes an invitation.
  Useful for canceling pending invitations.
  """
  def delete_invitation(%Invitation{} = invitation) do
    Repo.delete(invitation)
  end

  @doc """
  Checks if an email has any pending invitations.
  """
  def has_pending_invitation?(email) do
    case get_pending_invitation_by_email(email) do
      nil -> false
      %Invitation{} -> true
    end
  end

  @doc """
  Cleans up expired invitations.
  You might want to run this periodically using a scheduler like Quantum.
  """
  def cleanup_expired_invitations do
    now = DateTime.utc_now()

    Invitation
    |> where([i], i.expires_at < ^now)
    |> where([i], is_nil(i.accepted_at))
    |> Repo.delete_all()
  end

  # Helper function to validate invitation token
  def verify_invitation_token(token) do
    # Implement your token verification logic here
    # This could be useful if you're using tokens in invitation URLs
    case Phoenix.Token.verify(OnestackWeb.Endpoint, "invitation", token, max_age: 604_800) do
      {:ok, invitation_id} -> get_invitation(invitation_id)
      {:error, _} -> nil
    end
  end

  # Get a single invitation by ID
  def get_invitation(id) do
    Repo.get(Invitation, id)
  end

  # You might also want to add these helper functions:

  @doc """
  Resends an invitation email for a pending invitation.
  """
  def resend_invitation(%Invitation{} = invitation) do
    # if invitation_valid?(invitation) do
    #   inviter = Repo.get!(User, invitation.inviter_id)
    #   product_names = OnestackWeb.SubscribeLive.get_product_names(invitation.products)
    #   Onestack.Emails.send_team_invitation_email(invitation.email, inviter, product_names)
    # else
    #   {:error, :invalid_invitation}
    # end
  end

  defp invitation_valid?(%Invitation{} = invitation) do
    now = DateTime.utc_now()
    is_nil(invitation.accepted_at) && DateTime.compare(invitation.expires_at, now) == :gt
  end

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
  Lists all products that a user has access to through their team memberships.
  """
  def list_user_products(email) do
    # Query all teams where the user is either an admin or a member

    teams =
      Repo.all(
        from t in Team,
          where: t.admin_email == ^email or ^email in t.members
      )

    # Extract and flatten all products from the teams
    teams
    |> Enum.flat_map(& &1.products)
    |> Enum.uniq()
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
  def add_team_member(admin_user, team_member_email, products \\ []) do
    team = get_or_create_team(admin_user)

    new_members = [team_member_email | team.members]
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

      iex> list_team_members_by_admin(user)
      ["member1@example.com", "member2@example.com"]

  """
  def list_team_members_by_admin(user) do
    case get_team_by_admin(user) do
      nil -> []
      team -> team.members
    end
  end

  # Private helper functions

  def get_or_create_team(user) do
    case get_team_by_admin(user) do
      nil ->
        products = Map.get(user, :products, [])

        {:ok, team} =
          create_team(%{members: [user.email], products: products, admin_email: user.email})

        team

      team ->
        team
    end
  end

  def get_team_by_admin(user) do
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
