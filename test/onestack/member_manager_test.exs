defmodule Onestack.MemberManagerTest do
  use ExUnit.Case, async: true

  alias Onestack.MemberManager

  # Products whose services have been retired (see docs/adr). Teams created
  # before a retirement can still list them, so provisioning, removal and
  # password changes must skip them without trying to reach a database.
  @retired ~w(chatwoot kimai librechat nocodb penpot plane twenty)

  for product <- @retired do
    test "adding a member to retired #{product} is skipped" do
      assert MemberManager.add_member_to_product("member@example.com", unquote(product)) ==
               {:ok, {:skipped, :retired}}
    end

    test "removing a member from retired #{product} is skipped" do
      assert MemberManager.remove_member_from_product("member@example.com", unquote(product)) ==
               {:ok, {:skipped, :retired}}
    end

    test "a password change does not fail because of retired #{product}" do
      assert MemberManager.update_password_for_product("member@example.com", unquote(product)) ==
               {:ok, {:skipped, :retired}}
    end
  end

  test "a password change does not fail for a team that lists Matrix" do
    # Matrix passwords are not managed here; the clause must still return a
    # shape Accounts.update_user_password/3 accepts.
    assert {:ok, _} = MemberManager.update_password_for_product("member@example.com", "matrix")
  end
end
