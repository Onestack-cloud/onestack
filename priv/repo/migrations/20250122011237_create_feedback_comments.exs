defmodule Onestack.Repo.Migrations.CreateFeedbackComments do
  use Ecto.Migration

  def change do
    # Check if table exists before creating it
    unless table_exists?(:feedback_comments) do
      create table(:feedback_comments) do
        add :content, :text, null: false
        add :user_id, references(:users, on_delete: :nilify_all)
        add :feedback_id, references(:feedbacks, on_delete: :delete_all)
        timestamps()
      end

      create index(:feedback_comments, [:user_id])
      create index(:feedback_comments, [:feedback_id])
      create index(:feedback_comments, [:inserted_at])
    end
  end

  # Helper function to check if table exists for SQLite
  defp table_exists?(table_name) do
    query = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='#{table_name}';"
    %{rows: [[count]]} = repo().query!(query)
    count > 0
  end
end
