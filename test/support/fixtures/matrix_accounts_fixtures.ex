defmodule Onestack.MatrixAccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Onestack.MatrixAccounts` context.
  """

  @doc """
  Generate a matrix_user.
  """
  def matrix_user_fixture(attrs \\ %{}) do
    {:ok, matrix_user} =
      attrs
      |> Enum.into(%{
        email: "some email",
        matrix_id: "some matrix_id"
      })
      |> Onestack.MatrixAccounts.create_matrix_user()

    matrix_user
  end
end
