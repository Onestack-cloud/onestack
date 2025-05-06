defmodule Onestack.MemberManagementFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Onestack.MemberManagement` context.
  """

  @doc """
  Generate a member_credentials.
  """
  def member_credentials_fixture(attrs \\ %{}) do
    {:ok, member_credentials} =
      attrs
      |> Enum.into(%{
        email: "some email",
        hashed_password: "some hashed_password",
        job_id: "some job_id",
        password: "some password",
        product: "some product",
        salt: "some salt",
        status: "some status"
      })
      |> Onestack.MemberManagement.create_member_credentials()

    member_credentials
  end
end
