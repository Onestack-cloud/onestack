defmodule OnestackWeb.FeedbackLive.FormComponent do
  use OnestackWeb, :live_component

  alias Onestack.Feedback

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>What functionality would you like to see on Onestack?</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="feedback-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:title]}
          type="text"
          label="Feature or functionality"
          placeholder="e.g., 'Accounting/bookkeeping software' or 'Alternative to Xero'"
        />
        <.input
          field={@form[:content]}
          type="textarea"
          label="Description"
          placeholder="Tell us what functionality you need:
• Explain your specific use cases and requirements
• Note: We'll implement similar functionality, not provide access to the actual products"
        />
        <.input
          field={@form[:source_url]}
          type="url"
          label="Reference link (optional)"
          placeholder="Link to an example product with the functionality you're looking for"
        />

        <:actions>
          <.button phx-disable-with="Saving...">Submit Suggestion</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{feedback: feedback} = assigns, socket) do
    changeset = Feedback.change_feedback(feedback)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:current_user, assigns.current_user)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"feedback" => feedback_params}, socket) do
    changeset =
      socket.assigns.feedback
      |> Feedback.change_feedback(feedback_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"feedback" => feedback_params}, socket) do
    feedback_params = Map.put(feedback_params, "user_id", socket.assigns.current_user.id)
    save_feedback(socket, socket.assigns.action, feedback_params)
  end

  defp save_feedback(socket, :edit, feedback_params) do
    case Feedback.update_feedback(socket.assigns.feedback, feedback_params) do
      {:ok, feedback} ->
        notify_parent({:saved, feedback})

        {:noreply,
         socket
         |> put_flash(:info, "Product suggestion updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_feedback(socket, :new, feedback_params) do
    case Feedback.create_feedback(feedback_params) do
      {:ok, feedback} ->
        notify_parent({:saved, feedback})

        {:noreply,
         socket
         |> put_flash(:info, "Product suggestion submitted successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), msg)
end
