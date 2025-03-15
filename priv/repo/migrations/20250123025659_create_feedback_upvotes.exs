defmodule Onestack.Repo.Migrations.CreateFeedbackUpvotes do
  use Ecto.Migration

  def change do
    unless table_exists?(:feedback_upvotes) do
      create table(:feedback_upvotes) do
        add :user_id, references(:users, on_delete: :delete_all), null: false
        add :feedback_id, references(:feedbacks, on_delete: :delete_all), null: false

        timestamps()
      end

      create unique_index(:feedback_upvotes, [:user_id, :feedback_id])
    end
  end

  defp table_exists?(table_name) do
    query = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='#{table_name}';"
    %{rows: [[count]]} = repo().query!(query)
    count > 0
  end
end
