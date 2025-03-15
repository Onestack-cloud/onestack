defmodule OnestackWeb.UserForgotPasswordLive do
  use OnestackWeb, :live_view

  alias Onestack.Accounts

  def render(assigns) do
    ~H"""
    <main id="forgot_password" class="w-full flex h-full justify-center items-center mx-auto p-6">
      <div class="w-full max-w-md">
        <div class="bg-white border border-gray-200 rounded-xl shadow-sm dark:bg-neutral-900 dark:border-neutral-700">
          <div class="p-4 sm:p-7">
            <div class="text-center">
              <h1 class="block text-2xl font-bold text-gray-800 dark:text-white">Forgot password?</h1>
              <p class="mt-2 text-sm text-gray-600 dark:text-neutral-400">
                Remember your password?
                <.link
                  navigate={~p"/users/log_in"}
                  class="text-blue-600 decoration-2 hover:underline focus:outline-none focus:underline font-medium dark:text-blue-500"
                >
                  Sign in here
                </.link>
              </p>
            </div>
            <div class="mt-5">
              <.simple_form for={@form} id="reset_password_form" phx-submit="send_email">
                <.input
                  field={@form[:email]}
                  type="email"
                  placeholder="your@email.com"
                  label="Email address"
                  required
                />
                <:actions>
                  <.button phx-disable-with="Sending..." class="w-full">
                    Send password reset instructions
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

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"), page_title: "Forgot Password?")}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
