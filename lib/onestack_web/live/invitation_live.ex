defmodule OnestackWeb.InvitationLive do
  use OnestackWeb, :live_view
  alias Onestack.MemberManager

  def mount(%{"token" => token}, _session, socket) do
    # Fetch and clear the results
    results = MemberManager.get_job_results(token, true)

    if Enum.empty?(results) do
      {:ok,
       socket
       |> put_flash(:error, "Account information not found or already accessed.")
       |> redirect(to: "/")}
    else
      {:ok, assign(socket, results: results, format: :csv, full_view: false)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-4">
      <div class="mb-8">
        <div class="flex justify-between items-center mb-4">
          <h1 class="text-3xl font-bold">Your Account Information</h1>
          <div class="mb-4 flex justify-end">
            <label class="label cursor-pointer flex items-center">
              <span class="label-text mr-2">CSV</span>
              <input
                type="checkbox"
                class="toggle"
                phx-click="toggle_format"
                checked={@format == :json}
              />
              <span class="label-text ml-2">JSON</span>
            </label>
          </div>
        </div>
        <div role="alert" class="alert alert-warning">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-6 w-6 shrink-0 stroke-current"
            fill="none"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
            />
          </svg>
          <span>
            Make sure to import your credentials to your preferred password manager as they will be erased from our systems when you leave this page!
          </span>
        </div>
      </div>

      <div class="divider"></div>

      <div class="mb-8">
        <h2 class="text-2xl font-semibold mb-4">Onestack credentials</h2>
        <div class="bg-base-200 p-4 rounded-lg max-h-60 overflow-y-auto">
          <pre id="formatted-data" class="whitespace-pre-wrap break-words"><code><%= format_preview(@results, @format) %></code></pre>
        </div>
      </div>

      <div class="mb-8">
        <button
          id="copy-button"
          phx-hook="CopyToClipboard"
          class="btn btn-primary"
          aria-label="Copy formatted data to clipboard"
        >
          Copy to Clipboard
        </button>
        <span id="copy-feedback" class="ml-2 text-success hidden">Copied successfully!</span>
      </div>

      <div class="divider"></div>

      <div class="mb-8">
        <div role="alert" class="alert">
          <div class="flex items-center">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="stroke-current flex-shrink-0 w-6 h-6 mr-2"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              >
              </path>
            </svg>
            <span>
              This export is compatible with Bitwarden and many other password managers. Check your password manager's documentation for import instructions.
            </span>
          </div>
        </div>
        <div class="collapse collapse-plus bg-base-200">
          <input type="checkbox" />
          <div class="collapse-title text-xl font-medium flex items-center">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-6 w-6 mr-2"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            Not an existing Bitwarden user?
          </div>
          <div class="collapse-content">
            <p class="mb-4">
              Get started with Bitwarden to securely manage your passwords across all your devices.
            </p>
            <div class="flex justify-end space-x-2">
              <a
                href="https://bitwarden.com/get-started/"
                target="_blank"
                rel="noopener noreferrer"
                class="btn btn-primary"
              >
                Get Started with Bitwarden
              </a>
              <div class="tooltip" data-tip="Learn how to import your credentials">
                <a
                  href="https://bitwarden.com/help/import-data/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="btn btn-secondary"
                >
                  Import Guide
                </a>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("toggle_format", _, socket) do
    new_format = if socket.assigns.format == :json, do: :csv, else: :json
    {:noreply, assign(socket, format: new_format)}
  end

  defp format_accounts(accounts, :csv) do
    headers =
      "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n"

    rows =
      Enum.map(accounts, fn {product, info} ->
        [
          "Onestack",
          "1",
          "login",
          "#{product} Onestack",
          "",
          "",
          "",
          "https://#{product}.onestack.cloud",
          escape_csv(info.email),
          escape_csv(info.password),
          ""
        ]
        |> Enum.join(",")
      end)

    headers <> Enum.join(rows, "\n")
  end

  def handle_event("set_format", %{"format" => format}, socket) do
    {:noreply, assign(socket, format: String.to_atom(format))}
  end

  def handle_event("toggle_full_view", _, socket) do
    {:noreply, assign(socket, full_view: !socket.assigns.full_view)}
  end

  defp format_preview(results, format) do
    results
    |> Enum.take(3)
    |> format_accounts(format)
  end

  defp format_accounts(accounts, :json) do
    items =
      Enum.map(accounts, fn {product, info} ->
        %{
          "id" => Ecto.UUID.generate(),
          "organizationId" => nil,
          "folderId" => nil,
          "type" => 1,
          "reprompt" => 0,
          "name" => "#{product} Onestack",
          "notes" => "",
          "favorite" => true,
          "fields" => [],
          "login" => %{
            "uris" => [
              %{
                "match" => nil,
                "uri" => "https://#{product}.onestack.cloud"
              }
            ],
            "username" => info.email,
            "password" => info.password,
            "totp" => nil
          },
          "collectionIds" => nil,
          "revisionDate" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "creationDate" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "deletedDate" => nil,
          "passwordHistory" => []
        }
      end)

    json_data = %{
      "folders" => [
        %{
          "id" => Ecto.UUID.generate(),
          "name" => "Onestack"
        }
      ],
      "items" => items
    }

    Jason.encode!(json_data, pretty: true)
  end

  defp escape_csv(field) do
    field = to_string(field)

    if String.contains?(field, [",", "\"", "\n"]) do
      "\"#{String.replace(field, "\"", "\"\"")}\""
    else
      field
    end
  end

  defp error_message(:not_found), do: "Invalid invitation link."
  defp error_message(:expired), do: "This invitation has expired."
  defp error_message(:already_used), do: "This invitation has already been used."
end
