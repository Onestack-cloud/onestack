defmodule OnestackWeb.InvitationLive do
  use OnestackWeb, :live_view
  alias Onestack.MemberManager

  def mount(%{"token" => "test"}, _session, socket) do
    test_results = %{
      "product1" => %{email: "test1@example.com", password: "password1"},
      "product2" => %{email: "test2@example.com", password: "password2"},
      "product3" => %{email: "test3@example.com", password: "password3"}
    }

    {:ok,
     assign(socket, results: test_results, format: :csv, full_view: false, dropdown_open: false)}
  end

  def mount(%{"token" => token}, _session, socket) do
    # Fetch and clear the results
    results = MemberManager.get_job_results(token, false)

    if Enum.empty?(results) do
      {:ok,
       socket
       |> put_flash(:error, "Account information not found or already accessed.")
       |> redirect(to: "/")}
    else
      {:ok,
       assign(socket, results: results, format: :csv, full_view: false, dropdown_open: false)}
    end
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
                "uri" =>
                  if product == "matrix" do
                    "https://app.element.io/"
                  else
                    "https://#{product}.onestack.cloud"
                  end
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

  defp format_accounts(accounts, :human) do
    Enum.map(accounts, fn {product, info} ->
      %{
        product: product,
        email: info.email,
        password: info.password,
        login_link:
          if(product == "matrix",
            do: "https://app.element.io/",
            else: "https://#{product}.onestack.cloud"
          )
      }
    end)
  end

  def handle_event("toggle_dropdown", _, socket) do
    {:noreply, assign(socket, dropdown_open: !socket.assigns.dropdown_open)}
  end

  def handle_event("close_dropdown", _, socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  def handle_event("change_format", %{"format" => format}, socket) do
    {:noreply, assign(socket, format: String.to_atom(format), dropdown_open: false)}
  end

  def handle_event("toggle_full_view", _, socket) do
    {:noreply, assign(socket, full_view: !socket.assigns.full_view)}
  end

  defp format_preview(results, :human) do
    results
    |> Enum.take(3)
    |> format_accounts(:human)
  end

  defp format_preview(results, format) do
    results
    |> Enum.take(3)
    |> format_accounts(format)
  end

  defp escape_csv(field) do
    field = to_string(field)

    if String.contains?(field, [",", "\"", "\n"]) do
      "\"#{String.replace(field, "\"", "\"\"")}\""
    else
      field
    end
  end

  # defp error_message(:not_found), do: "Invalid invitation link."
  # defp error_message(:expired), do: "This invitation has expired."
  # defp error_message(:already_used), do: "This invitation has already been used."
end
