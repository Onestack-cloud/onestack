defmodule Onestack.TeamsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Onestack.Teams` context.
  """

  @doc """
  Generate a team.
  """
  def team_fixture(attrs \\ %{}) do
    {:ok, team} =
      attrs
      |> Enum.into(%{
        members: ["member@example.com"],
        products: ["option1", "option2"],
        admin_email: "admin@example.com"
      })
      |> Onestack.Teams.create_team()

    team
  end
end
