defmodule OnestackWeb.UserRegistrationLive do
  use OnestackWeb, :live_view

  alias Onestack.{Accounts, Teams}

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm my-16 min-h-screen">
      <div class="bg-base-200 p-8 rounded-xl shadow-lg border border-base-300">
        <div class="mb-8">
          <div class="text-4xl font-bold text-center mb-2">Create Account</div>
          <div class="badge badge-primary badge-lg mx-auto block w-fit">New User Registration</div>
        </div>

        <%= if not is_nil(@admin_name) do %>
          <div class="alert alert-info mb-6">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              class="stroke-current shrink-0 w-6 h-6"
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

          <div class="my-4">
            <div class="bg-gradient-to-r from-base-100 to-base-200 rounded-full p-1 shadow-lg border border-base-300 flex items-center justify-center space-x-6 hover:shadow-xl transition-shadow duration-300">
              <%= for product <- @products do %>
                <div class="flex items-center justify-center bg-base-100 rounded-full p-1 backdrop-blur-sm">
                  <img
                    src={"https://onestack-images.pages.dev/#{URI.encode_www_form(product)}.png"}
                    class="h-8 w-8 mask mask-circle object-contain hover:scale-110 transition-transform duration-200"
                    alt={product}
                  />
                </div>
              <% end %>
            </div>
          </div>
        <% end %>

        <.simple_form
          for={@form}
          id="registration_form"
          phx-submit="save"
          phx-change="validate"
          phx-trigger-action={@trigger_submit}
          action={~p"/users/log_in?_action=registered"}
          method="post"
        >
          <.error :if={@check_errors}>
            Oops, something went wrong! Please check the errors below.
          </.error>

          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            required
            autocomplete="username email"
            id="email"
            placeholder="Email"
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            required
            autocomplete="new-password"
          />
          <:actions>
            <.button phx-disable-with="Creating account..." class="w-full btn-primary">
              Create Account
            </.button>
          </:actions>
        </.simple_form>

        <div class="text-center mt-6 text-sm">
          Already have an account?
          <.link navigate={~p"/users/log_in"} class="font-semibold text-primary hover:underline">
            Log in
          </.link>
        </div>
      </div>
    </div>
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
            Teams.accept_invitation(invitation)

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
        admin_name: admin_name
      )
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        # {:ok, _} =
        #   Accounts.deliver_user_confirmation_instructions(
        #     user,
        #     &url(~p"/users/confirm/#{&1}")
        #   )
        case Teams.get_pending_invitation(user.email) do
          %Teams.Invitation{} = invitation ->
            Teams.accept_invitation(invitation, user)
            # Process the team member addition
            product_names = OnestackWeb.SubscribeLive.get_product_names(invitation.products)
            Onestack.MemberManager.add_member(user.email, product_names)

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
