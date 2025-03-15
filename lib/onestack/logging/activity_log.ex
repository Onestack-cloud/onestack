defmodule Onestack.Logging.ActivityLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "activity_logs" do
    field :action, :string
    field :entity_type, :string
    field :entity_id, :integer
    field :changes, :map
    field :user_id, :id
    field :organisation_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(activity_log, attrs) do
    activity_log
    |> cast(attrs, [:action, :entity_type, :entity_id, :changes])
    |> validate_required([:action, :entity_type, :entity_id])
  end
end
