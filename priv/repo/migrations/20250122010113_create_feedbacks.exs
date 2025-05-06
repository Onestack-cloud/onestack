defmodule Onestack.Repo.Migrations.CreateFeedbacks do
  use Ecto.Migration

  def change do
    unless table_exists?(:feedbacks) do
      create table(:feedbacks) do
        add :title, :string, null: false
        add :content, :text, null: false
        add :status, :string, default: "Open"
        add :upvotes_count, :integer, default: 0
        add :source_url, :string
        add :user_id, references(:users, on_delete: :nilify_all)

        timestamps()
      end

      create index(:feedbacks, [:user_id])
      create index(:feedbacks, [:inserted_at])
      create index(:feedbacks, [:upvotes_count])
    end
  end

  # Helper function to check if table exists for SQLite
  defp table_exists?(table_name) do
    query = "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='#{table_name}';"
    %{rows: [[count]]} = repo().query!(query)
    count > 0
  end
end
