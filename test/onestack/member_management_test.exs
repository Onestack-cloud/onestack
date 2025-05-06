defmodule Onestack.MemberManagementTest do
  use Onestack.DataCase

  alias Onestack.MemberManagement

  describe "member_credentials" do
    alias Onestack.MemberManagement.MemberCredentials

    import Onestack.MemberManagementFixtures

    @invalid_attrs %{
      status: nil,
      product: nil,
      password: nil,
      job_id: nil,
      email: nil,
      hashed_password: nil,
      salt: nil
    }

    test "list_member_credentials/0 returns all member_credentials" do
      member_credentials = member_credentials_fixture()
      assert MemberManagement.list_member_credentials() == [member_credentials]
    end

    test "get_member_credentials!/1 returns the member_credentials with given id" do
      member_credentials = member_credentials_fixture()
      assert MemberManagement.get_member_credentials!(member_credentials.id) == member_credentials
    end

    test "create_member_credentials/1 with valid data creates a member_credentials" do
      valid_attrs = %{
        status: "some status",
        product: "some product",
        password: "some password",
        job_id: "some job_id",
        email: "some email",
        hashed_password: "some hashed_password",
        salt: "some salt"
      }

      assert {:ok, %MemberCredentials{} = member_credentials} =
               MemberManagement.create_member_credentials(valid_attrs)

      assert member_credentials.status == "some status"
      assert member_credentials.product == "some product"
      assert member_credentials.password == "some password"
      assert member_credentials.job_id == "some job_id"
      assert member_credentials.email == "some email"
      assert member_credentials.hashed_password == "some hashed_password"
      assert member_credentials.salt == "some salt"
    end

    test "create_member_credentials/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               MemberManagement.create_member_credentials(@invalid_attrs)
    end

    test "update_member_credentials/2 with valid data updates the member_credentials" do
      member_credentials = member_credentials_fixture()

      update_attrs = %{
        status: "some updated status",
        product: "some updated product",
        password: "some updated password",
        job_id: "some updated job_id",
        email: "some updated email",
        hashed_password: "some updated hashed_password",
        salt: "some updated salt"
      }

      assert {:ok, %MemberCredentials{} = member_credentials} =
               MemberManagement.update_member_credentials(member_credentials, update_attrs)

      assert member_credentials.status == "some updated status"
      assert member_credentials.product == "some updated product"
      assert member_credentials.password == "some updated password"
      assert member_credentials.job_id == "some updated job_id"
      assert member_credentials.email == "some updated email"
      assert member_credentials.hashed_password == "some updated hashed_password"
      assert member_credentials.salt == "some updated salt"
    end

    test "update_member_credentials/2 with invalid data returns error changeset" do
      member_credentials = member_credentials_fixture()

      assert {:error, %Ecto.Changeset{}} =
               MemberManagement.update_member_credentials(member_credentials, @invalid_attrs)

      assert member_credentials == MemberManagement.get_member_credentials!(member_credentials.id)
    end

    test "delete_member_credentials/1 deletes the member_credentials" do
      member_credentials = member_credentials_fixture()

      assert {:ok, %MemberCredentials{}} =
               MemberManagement.delete_member_credentials(member_credentials)

      assert_raise Ecto.NoResultsError, fn ->
        MemberManagement.get_member_credentials!(member_credentials.id)
      end
    end

    test "change_member_credentials/1 returns a member_credentials changeset" do
      member_credentials = member_credentials_fixture()
      assert %Ecto.Changeset{} = MemberManagement.change_member_credentials(member_credentials)
    end
  end
end
