defmodule Onestack.Repo.Migrations.CreateFeedbackComments do
  use Ecto.Migration

  def change do
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
