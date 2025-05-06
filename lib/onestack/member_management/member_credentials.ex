defmodule Onestack.MemberManagement.MemberCredentials do
  use Ecto.Schema
  import Ecto.Changeset

  schema "member_credentials" do
    field :product, :string
    field :password, :string
    field :job_id, :string
    field :email, :string
    field :hashed_password, :string
    field :salt, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(member_credentials, attrs) do
    member_credentials
    |> cast(attrs, [:job_id, :email, :product, :password, :hashed_password, :salt])
    |> validate_required([:job_id, :email, :product, :password, :hashed_password, :salt])
  end
end
