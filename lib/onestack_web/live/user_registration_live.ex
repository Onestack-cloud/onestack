defmodule OnestackWeb.UserRegistrationLive do
  use OnestackWeb, :live_view

  alias Onestack.{Accounts, Teams}

  def render(assigns) do
    ~H"""
    <main id="log_in" class="w-full flex min-h-screen justify-center items-center mx-auto p-6">
      <div class="w-full max-w-md">
        <div class="mt-7 bg-white border border-gray-200 rounded-xl shadow-sm dark:bg-neutral-900 dark:border-neutral-700">
          <div class="p-4 sm:p-7">
            <div class="text-center">
              <h1 class="block text-2xl font-bold text-gray-800 dark:text-white">Create Account</h1>
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

              <div class="mt-5">
                <div class="bg-gradient-to-r from-gray-50 to-gray-100 dark:from-neutral-800 dark:to-neutral-700 rounded-full p-1 shadow-sm border border-gray-200 dark:border-neutral-600 flex items-center justify-center space-x-6">
                  <%= for product <- @products do %>
                    <div class="flex items-center justify-center bg-white dark:bg-neutral-800 rounded-full p-1">
                      <img
                        src={"https://onestack-images.pages.dev/#{URI.encode_www_form(product)}.png"}
                        class="h-8 w-8 rounded-full object-contain hover:scale-110 transition-transform duration-200"
                        alt={product}
                      />
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <div class="mt-5">
              <.simple_form
                for={@form}
                id="registration_form"
                phx-submit="save"
                phx-change="validate"
                phx-trigger-action={@trigger_submit}
                action={~p"/users/log_in?_action=registered"}
                method="post"
                class="grid gap-y-4"
              >
                <.error :if={@check_errors} class="text-sm text-red-600 mt-2">
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
        case Teams.get_pending_invitation(invitation_id) do
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
        case Teams.get_pending_invitation(invitation_id) do
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
