defmodule OnestackWeb.FeedbackLive.Show do
  use OnestackWeb, :live_view

  alias Onestack.Feedback

  @impl true
  def mount(_params, session, socket) do
    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Onestack.Accounts.get_user_by_session_token(user_token)
      end
    {:ok,
     socket
     |> assign(:current_user, current_user)
     |> stream(:comments, [])
     |> assign(:comment_form, to_form(%{"content" => ""}))}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    feedback = Feedback.get_feedback!(id)
    feedback =
      if socket.assigns.current_user do
        Map.put(feedback, :has_upvoted, Feedback.has_upvoted?(feedback, socket.assigns.current_user.id))
      else
        Map.put(feedback, :has_upvoted, false)
      end

    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:feedback, feedback)
     |> stream(:comments, feedback.comments)}
  end

  @impl true
  def handle_event("upvote", %{"id" => id}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "You must be logged in to upvote.")
         |> redirect(to: ~p"/users/log_in")}

      user ->
        feedback = Feedback.get_feedback!(id)
        was_upvoted = Feedback.has_upvoted?(feedback, user.id)

        case Feedback.upvote_feedback(feedback, user.id) do
          {:ok, feedback} ->
            feedback = Map.put(feedback, :has_upvoted, !was_upvoted)
            {:noreply, assign(socket, :feedback, feedback)}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> put_flash(:error, "Unable to process your upvote at this time.")}
        end
    end
  end

  @impl true
  def handle_event("save-comment", %{"content" => content}, socket) do
    case socket.assigns.current_user do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "You must be logged in to comment.")
         |> redirect(to: ~p"/users/log_in")}

      user ->
        attrs = %{
          content: content,
          user_id: user.id,
          feedback_id: socket.assigns.feedback.id
        }

        case Feedback.create_comment(attrs) do
          {:ok, comment} ->
            comment = %{comment | user: user}

            {:noreply,
             socket
             |> stream_insert(:comments, comment)
             |> assign(:comment_form, to_form(%{"content" => ""}))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :comment_form, to_form(changeset))}
        end
    end
  end

  @impl true
  def handle_event("delete-comment", %{"value" => %{"id" => id}}, socket) do
    comment = Feedback.get_comment!(id)

    if socket.assigns.current_user && socket.assigns.current_user.id == comment.user_id do
      case Feedback.delete_comment(comment) do
        {:ok, _comment} ->
          {:noreply, stream_delete(socket, :comments, comment)}

        {:error, _changeset} ->
          {:noreply,
           socket
           |> put_flash(:error, "Unable to delete comment at this time.")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "You can only delete your own comments.")}
    end
  end

  defp page_title(:show), do: "Show Feedback"
  defp page_title(:edit), do: "Edit Product"
end
