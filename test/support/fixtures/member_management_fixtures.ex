defmodule Onestack.MemberManagementFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Onestack.MemberManagement.MemberCredentials` schema.
  """

  @doc """
  Generate a member_credentials.
  """
  def member_credentials_fixture(attrs \\ %{}) do
    {:ok, member_credentials} =
      attrs
      |> Enum.into(%{
        email: "member@example.com",
        hashed_password: "some hashed_password",
        job_id: "some job_id",
        password: "some password",
        product: "some product",
        salt: "some salt"
      })
      |> then(fn attrs ->
        %Onestack.MemberManagement.MemberCredentials{}
        |> Onestack.MemberManagement.MemberCredentials.changeset(attrs)
        |> Onestack.Repo.insert()
      end)

    member_credentials
  end
end
