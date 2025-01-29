defmodule OnestackWeb.UserLoginLive do
  use OnestackWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md my-16 min-h-screen">
      <div class="bg-base-200 p-8 rounded-xl shadow-lg border border-base-300">
        <div class="mb-8">
          <div class="text-4xl font-bold text-center mb-2">Welcome Back</div>
          <div class="badge badge-secondary badge-lg mx-auto block w-fit">Sign In</div>
        </div>

        <.simple_form for={@form} id="login_form" action={~p"/users/log_in"} phx-update="ignore">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            required
            class="w-full"
            placeholder="your@email.com"
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            required
            placeholder="••••••••"
          />

          <div class="flex justify-between items-center mb-4">
            <.input field={@form[:remember_me]} type="checkbox" label="Keep me logged in" />
            <.link href={~p"/users/reset_password"} class="text-sm font-semibold link link-hover">
              Forgot password?
            </.link>
          </div>

          <:actions>
            <.button phx-disable-with="Signing in..." class="w-full btn-secondary">
              Sign In <span aria-hidden="true">→</span>
            </.button>
          </:actions>
        </.simple_form>

        <div class="text-center mt-6 text-sm">
          New to Onestack?
          <.link navigate={~p"/users/register"} class="font-semibold link link-hover">
            Create an account
          </.link>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form, page_title: "Log in"), temporary_assigns: [form: form]}
  end
end
