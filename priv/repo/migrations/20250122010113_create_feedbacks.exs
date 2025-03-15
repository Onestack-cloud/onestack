defmodule Onestack.Repo.Migrations.CreateFeedbacks do
  use Ecto.Migration

  def change do
    execute "DROP TABLE IF EXISTS feedbacks"

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
