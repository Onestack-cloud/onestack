defmodule Onestack.Repo.Migrations.CreateFeedbackUpvotes do
  use Ecto.Migration

  def change do
    create table(:feedback_upvotes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :feedback_id, references(:feedbacks, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:feedback_upvotes, [:user_id, :feedback_id])
  end
end
