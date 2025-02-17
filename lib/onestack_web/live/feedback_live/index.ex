defmodule OnestackWeb.FeedbackLive.Index do
  use OnestackWeb, :live_view
  alias Onestack.Feedback

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Onestack.PubSub, "feedbacks")

    current_user =
      case session["user_token"] do
        nil -> nil
        user_token -> Onestack.Accounts.get_user_by_session_token(user_token)
      end

    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:page_title, "Feature suggestions")
      |> assign(:sort, :most_votes)
      |> assign(:filter, :all)
      |> assign(:search_query, "")
      |> assign(:comment_form, to_form(%{"content" => ""}))
      |> load_feedbacks()

    {:ok, socket}
  end

  defp load_feedbacks(socket) do
    require Logger
    Logger.info("Loading feedbacks with sort: #{inspect(socket.assigns.sort)}")

    feedbacks =
      Feedback.list_feedbacks(
        socket.assigns.sort,
        socket.assigns.search_query
      )

    Logger.info("Loaded #{length(feedbacks)} feedbacks")

    feedbacks =
      if socket.assigns.current_user do
        Enum.map(feedbacks, fn feedback ->
          Map.put(
            feedback,
            :has_upvoted,
            Feedback.has_upvoted?(feedback, socket.assigns.current_user.id)
          )
        end)
      else
        Enum.map(feedbacks, fn feedback ->
          Map.put(feedback, :has_upvoted, false)
        end)
      end

    socket
    |> stream(:feedbacks, feedbacks, reset: true)
    |> stream(:comments, [])
  end

  @impl true
  def handle_event("sort", %{"sort" => sort}, socket) do
    require Logger
    Logger.info("Sort event received with sort: #{inspect(sort)}")

    sort = String.to_existing_atom(sort)
    Logger.info("Converting sort to atom: #{inspect(sort)}")

    {:noreply, socket |> assign(:sort, sort) |> load_feedbacks()}
  end

  def handle_event("sort", %{"value" => value}, socket) do
    require Logger
    Logger.info("Sort event received with value: #{inspect(value)}")

    # Parse the form data
    params = URI.decode_query(value)
    sort = String.to_existing_atom(params["sort"] || "new")
    Logger.info("Converting sort to atom: #{inspect(sort)}")

    {:noreply, socket |> assign(:sort, sort) |> load_feedbacks()}
  end

  @impl true
  def handle_event("search", %{"key" => _key, "value" => query}, socket) do
    {:noreply, socket |> assign(:search_query, query) |> load_feedbacks()}
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
        feedback = Onestack.Feedback.get_feedback!(id)

        case Onestack.Feedback.toggle_upvote(feedback, user) do
          {:ok, _} -> {:noreply, load_feedbacks(socket)}
          {:error, _} -> {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    case socket.assigns.current_user do
      nil ->
        socket
        |> put_flash(:error, "You must be logged in to create a suggestion.")
        |> redirect(to: ~p"/users/log_in")

      _user ->
        socket
        |> assign(:page_title, "New feature suggestion")
        |> assign(:feedback, %Feedback.Feedback{})
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Feature Suggestion")
    |> assign(:feedback, Feedback.get_feedback!(id))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Feature Suggestions")
    |> assign(:feedback, nil)
  end

  @impl true
  def handle_info({:saved, _feedback}, socket) do
    {:noreply, load_feedbacks(socket)}
  end

  @impl true
  def handle_info({:feedback_created, feedback}, socket) do
    feedback =
      if socket.assigns.current_user do
        Map.put(
          feedback,
          :has_upvoted,
          Feedback.has_upvoted?(feedback, socket.assigns.current_user.id)
        )
      else
        Map.put(feedback, :has_upvoted, false)
      end

    {:noreply, stream_insert(socket, :feedbacks, feedback)}
  end

  defp list_feedbacks(sort, search_query) do
    Feedback.list_feedbacks()
    |> search_feedbacks(search_query)
  end

  defp search_feedbacks(query, nil), do: query
  defp search_feedbacks(query, ""), do: query

  defp search_feedbacks(query, search_query) do
    search_query = String.downcase(search_query)

    Enum.filter(query, fn feedback ->
      String.contains?(String.downcase(feedback.title), search_query) ||
        String.contains?(String.downcase(feedback.content), search_query)
    end)
  end

  defp relative_time(datetime) do
    now = DateTime.utc_now()

    datetime =
      case datetime do
        %NaiveDateTime{} -> DateTime.from_naive!(datetime, "Etc/UTC")
        %DateTime{} -> datetime
      end

    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 2_592_000 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%B %d, %Y")
    end
  end

  defp truncate_url(url, max_length: max_length) do
    if String.length(url) <= max_length do
      url
    else
      truncated = String.slice(url, 0, max_length - 3)
      truncated <> "..."
    end
  end
end
