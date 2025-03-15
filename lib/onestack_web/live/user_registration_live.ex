defmodule OnestackWeb.UserRegistrationLive do
  use OnestackWeb, :live_view

  alias Onestack.{Accounts, Teams}

  def render(assigns) do
    ~H"""
    <main
      id="log_in"
      class="flex flex-col items-center mt-20 px-6 py-8 mx-auto md:h-screen lg:py-0"
    >
      <div class="w-full max-w-md">
        <div class="bg-white dark:bg-gray-800 border border-gray-200 rounded-xl shadow-sm dark:border-neutral-700">
          <div class="p-4 sm:p-7">
            <div class="text-center">
              <h1 class="block text-2xl font-bold text-gray-800 dark:text-white">
                Create Account
              </h1>
              <p class="mt-2 text-sm text-gray-600 dark:text-neutral-400">
                Already have an account?
                <.link
                  navigate={~p"/users/log_in"}
                  class="text-blue-600 decoration-2 hover:underline focus:outline-none focus:underline font-medium dark:text-blue-500"
                >
                  Log in
                </.link>
              </p>
            </div>

            <%= if not is_nil(@admin_name) do %>
              <div class="mt-4 p-4 bg-blue-50 text-blue-800 rounded-lg dark:bg-blue-900/50 dark:text-blue-400">
                <div class="flex items-center">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    class="stroke-current shrink-0 w-6 h-6 me-2"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    >
                    </path>
                  </svg>
                  <span>You're joining <%= @admin_name %>'s stack</span>
                </div>
              </div>

              <div class="mt-8">
                <div class="bg-gradient-to-r from-gray-50 to-gray-100 dark:from-gray-800 dark:to-gray-700 rounded-2xl p-3 shadow-md border border-gray-200 dark:border-gray-600">
                  <div class="flex items-center justify-center space-x-4 sm:space-x-6">
                    <%= for product_name <- @products do %>
                      <% product_metadata =
                        Onestack.CatalogMonthly.ProductMetadata.get_metadata(
                          product_name
                        ) %>
                      <div class="group relative">
                        <div class="flex items-center justify-center bg-white dark:bg-gray-900 rounded-xl p-3 transition-all duration-300 ease-in-out transform group-hover:scale-110 group-hover:shadow-lg">
                          <Lucide.render
                            icon={product_metadata.icon}
                            class="h-8 w-8 text-blue-600 dark:text-blue-400"
                            alt={product_metadata.display_name}
                          />
                        </div>
                        <div class="absolute -bottom-2 left-1/2 transform -translate-x-1/2 opacity-0 group-hover:opacity-100 transition-opacity duration-300">
                          <div class="bg-gray-800 dark:bg-gray-200 text-white dark:text-gray-800 text-xs rounded py-1 px-2 whitespace-nowrap">
                            <%= product_metadata.display_name %>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

            <div class="mt-5">
              <.simple_form
                for={@form}
                id="registration_form"
                phx-submit="save"
                phx-trigger-action={@trigger_submit}
                action={~p"/users/log_in?_action=registered"}
                method="post"
                class="grid gap-y-4"
              >
                <.error
                  :if={@check_errors}
                  class="text-sm text-red-600 mt-2"
                >
                  Oops, something went wrong! Please check the errors below.
                </.error>

                <.input
                  field={@form[:email]}
                  type="email"
                  label="Email"
                  required
                  autocomplete="username email"
                  id="email"
                  placeholder="your@email.com"
                />
                <.input
                  field={@form[:first_name]}
                  type="text"
                  label="First Name"
                  required
                  autocomplete="given-name"
                  id="first_name"
                  placeholder="John"
                />
                <.input
                  field={@form[:last_name]}
                  type="text"
                  label="Last Name"
                  required
                  autocomplete="family-name"
                  id="last_name"
                  placeholder="Doe"
                />
                <.input
                  field={@form[:company_name]}
                  type="text"
                  label="Company Name"
                  required
                  autocomplete="organization"
                  id="company_name"
                  placeholder="Acme Inc."
                />
                <.input
                  field={@form[:password]}
                  type="password"
                  label="Password"
                  required
                  placeholder="••••••••"
                  autocomplete="new-password"
                />

                <:actions>
                  <.button phx-disable-with="Creating account...">
                    Create Account
                  </.button>
                </:actions>
              </.simple_form>
            </div>
          </div>
        </div>
      </div>
    </main>
    """
  end

  def mount(params, _session, socket) do
    invitation_id = Map.get(params, "invitation")
    changeset = Accounts.change_user_registration(%Accounts.User{})
    IO.inspect(invitation_id)

    {products, admin_name} =
      if is_nil(invitation_id) do
        {[], nil}
      else
        case Teams.get_pending_invitation_by_id(invitation_id) do
          %Teams.Invitation{} = invitation ->
            # Teams.accept_invitation(invitation)

            {
              Teams.list_user_products(invitation.recipient_email),
              Onestack.InvitationEmail.get_customer_first_name(invitation.admin_email)
            }

          nil ->
            {[], nil}
        end
      end

    socket =
      socket
      |> assign(
        trigger_submit: false,
        check_errors: false,
        page_title: "Register",
        products: products,
        admin_name: admin_name,
        invitation_id: invitation_id
      )
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    invitation_id = socket.assigns.invitation_id

    case Accounts.register_user(user_params) do
      {:ok, user} ->
        # {:ok, _} =
        #   Accounts.deliver_user_confirmation_instructions(
        #     user,
        #     &url(~p"/users/confirm/#{&1}")
        #   )
        case Teams.get_pending_invitation_by_id(invitation_id) do
          %Teams.Invitation{} = invitation ->
            Teams.accept_invitation(invitation)
            # Process the team member addition
            Onestack.MemberManager.add_member(user.email, socket.assigns.products)

          nil ->
            :ok
        end

        changeset = Accounts.change_user_registration(user)

        {:noreply,
         socket
         |> assign(trigger_submit: true)
         |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%Accounts.User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end
end
