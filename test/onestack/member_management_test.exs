defmodule Onestack.MemberManagementTest do
  use Onestack.DataCase

  alias Onestack.Repo

  describe "member_credentials" do
    alias Onestack.MemberManagement.MemberCredentials

    import Onestack.MemberManagementFixtures

    @valid_attrs %{
      product: "some product",
      password: "some password",
      job_id: "some job_id",
      email: "member@example.com",
      hashed_password: "some hashed_password",
      salt: "some salt"
    }

    @invalid_attrs %{
      product: nil,
      password: nil,
      job_id: nil,
      email: nil,
      hashed_password: nil,
      salt: nil
    }

    test "list_member_credentials/0 returns all member_credentials" do
      member_credentials = member_credentials_fixture()
      assert Repo.all(MemberCredentials) == [member_credentials]
    end

    test "get_member_credentials!/1 returns the member_credentials with given id" do
      member_credentials = member_credentials_fixture()
      assert Repo.get!(MemberCredentials, member_credentials.id) == member_credentials
    end

    test "create_member_credentials/1 with valid data creates a member_credentials" do
      changeset = MemberCredentials.changeset(%MemberCredentials{}, @valid_attrs)
      assert {:ok, %MemberCredentials{} = member_credentials} = Repo.insert(changeset)
      assert member_credentials.product == "some product"
      assert member_credentials.password == "some password"
      assert member_credentials.job_id == "some job_id"
      assert member_credentials.email == "member@example.com"
      assert member_credentials.hashed_password == "some hashed_password"
      assert member_credentials.salt == "some salt"
    end

    test "create_member_credentials/1 with invalid data returns error changeset" do
      changeset = MemberCredentials.changeset(%MemberCredentials{}, @invalid_attrs)
      assert {:error, %Ecto.Changeset{}} = Repo.insert(changeset)
    end

    test "update_member_credentials/2 with valid data updates the member_credentials" do
      member_credentials = member_credentials_fixture()

      update_attrs = %{
        product: "some updated product",
        password: "some updated password",
        job_id: "some updated job_id",
        email: "updated@example.com",
        hashed_password: "some updated hashed_password",
        salt: "some updated salt"
      }

      changeset = MemberCredentials.changeset(member_credentials, update_attrs)
      assert {:ok, %MemberCredentials{} = updated} = Repo.update(changeset)
      assert updated.product == "some updated product"
      assert updated.password == "some updated password"
      assert updated.job_id == "some updated job_id"
      assert updated.email == "updated@example.com"
      assert updated.hashed_password == "some updated hashed_password"
      assert updated.salt == "some updated salt"
    end

    test "update_member_credentials/2 with invalid data returns error changeset" do
      member_credentials = member_credentials_fixture()
      changeset = MemberCredentials.changeset(member_credentials, @invalid_attrs)
      assert {:error, %Ecto.Changeset{}} = Repo.update(changeset)
      assert member_credentials == Repo.get!(MemberCredentials, member_credentials.id)
    end

    test "delete_member_credentials/1 deletes the member_credentials" do
      member_credentials = member_credentials_fixture()
      assert {:ok, %MemberCredentials{}} = Repo.delete(member_credentials)
      assert_raise Ecto.NoResultsError, fn -> Repo.get!(MemberCredentials, member_credentials.id) end
    end

    test "change_member_credentials/1 returns a member_credentials changeset" do
      member_credentials = member_credentials_fixture()
      assert %Ecto.Changeset{} = MemberCredentials.changeset(member_credentials, %{})
    end
  end
end
