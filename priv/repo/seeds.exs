# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Onestack.Repo.insert!(%Onestack.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
alias Onestack.MatrixAccounts.MatrixUser

dummy_user = %{
  email: "test-example@example.com",
  matrix_id: "@test-example.com:matrix.onestack.cloud"
}

%MatrixUser{}
|> MatrixUser.changeset(dummy_user)
|> Onestack.Repo.insert!()
