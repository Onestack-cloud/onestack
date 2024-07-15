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
        member_email: "some member_email",
        products: ["option1", "option2"]
      })
      |> Onestack.Teams.create_team()

    team
  end
end
