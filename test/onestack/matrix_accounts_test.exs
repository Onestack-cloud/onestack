defmodule Onestack.MatrixAccountsTest do
  use Onestack.DataCase

  alias Onestack.MatrixAccounts

  describe "users" do
    alias Onestack.MatrixAccounts.MatrixUser

    import Onestack.MatrixAccountsFixtures

    @invalid_attrs %{email: nil, matrix_id: nil}

    test "list_users/0 returns all users" do
      matrix_user = matrix_user_fixture()
      assert MatrixAccounts.list_users() == [matrix_user]
    end

    test "get_matrix_user!/1 returns the matrix_user with given id" do
      matrix_user = matrix_user_fixture()
      assert MatrixAccounts.get_matrix_user!(matrix_user.id) == matrix_user
    end

    test "create_matrix_user/1 with valid data creates a matrix_user" do
      valid_attrs = %{email: "some email", matrix_id: "some matrix_id"}

      assert {:ok, %MatrixUser{} = matrix_user} = MatrixAccounts.create_matrix_user(valid_attrs)
      assert matrix_user.email == "some email"
      assert matrix_user.matrix_id == "some matrix_id"
    end

    test "create_matrix_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = MatrixAccounts.create_matrix_user(@invalid_attrs)
    end

    test "update_matrix_user/2 with valid data updates the matrix_user" do
      matrix_user = matrix_user_fixture()
      update_attrs = %{email: "some updated email", matrix_id: "some updated matrix_id"}

      assert {:ok, %MatrixUser{} = matrix_user} =
               MatrixAccounts.update_matrix_user(matrix_user, update_attrs)

      assert matrix_user.email == "some updated email"
      assert matrix_user.matrix_id == "some updated matrix_id"
    end

    test "update_matrix_user/2 with invalid data returns error changeset" do
      matrix_user = matrix_user_fixture()

      assert {:error, %Ecto.Changeset{}} =
               MatrixAccounts.update_matrix_user(matrix_user, @invalid_attrs)

      assert matrix_user == MatrixAccounts.get_matrix_user!(matrix_user.id)
    end

    test "delete_matrix_user/1 deletes the matrix_user" do
      matrix_user = matrix_user_fixture()
      assert {:ok, %MatrixUser{}} = MatrixAccounts.delete_matrix_user(matrix_user)
      assert_raise Ecto.NoResultsError, fn -> MatrixAccounts.get_matrix_user!(matrix_user.id) end
    end

    test "change_matrix_user/1 returns a matrix_user changeset" do
      matrix_user = matrix_user_fixture()
      assert %Ecto.Changeset{} = MatrixAccounts.change_matrix_user(matrix_user)
    end
  end
end
