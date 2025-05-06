defmodule Onestack.Teams.Team do
  use Ecto.Schema
  import Ecto.Changeset

  schema "teams" do
    field :members, {:array, :string}
    field :products, {:array, :string}
    field :admin_email, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team, attrs) do
    team
    |> cast(attrs, [:members, :products, :admin_email])
    |> validate_required([:members, :admin_email])
    |> validate_no_duplicates(:members)
    |> validate_no_duplicates(:products)
  end

  defp validate_no_duplicates(changeset, field) do
    validate_change(changeset, field, fn _, values ->
      if length(Enum.uniq(values)) != length(values) do
        [{field, "must not contain duplicates"}]
      else
        []
      end
    end)
  end
end
