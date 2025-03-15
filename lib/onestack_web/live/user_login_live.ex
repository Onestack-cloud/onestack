defmodule OnestackWeb.UserLoginLive do
  use OnestackWeb, :live_view

  def render(assigns) do
    ~H"""
    <main id="log_in" class="w-full flex min-h-screen justify-center items-center mx-auto p-6">
      <div class="w-full max-w-md">
        <div class="mt-7 bg-white border border-gray-200 rounded-xl shadow-sm dark:bg-neutral-900 dark:border-neutral-700">
          <div class="p-4 sm:p-7">
            <div class="text-center">
              <h1 class="block text-2xl font-bold text-gray-800 dark:text-white">Sign in</h1>
              <p class="mt-2 text-sm text-gray-600 dark:text-neutral-400">
                Don't have an account yet?
                <.link
                  navigate={~p"/users/register"}
                  class="text-blue-600 decoration-2 hover:underline focus:outline-none focus:underline font-medium dark:text-blue-500"
                >
                  Sign up here
                </.link>
              </p>
            </div>

            <div class="mt-5">
              <.simple_form
                for={@form}
                id="login_form"
                action={~p"/users/log_in"}
                phx-update="ignore"
                class="grid gap-y-4"
              >
                <div class="relative">
                  <.input
                    field={@form[:email]}
                    type="email"
                    label="Email address"
                    required
                    class="py-3 px-4 block w-full border-gray-200 rounded-lg text-sm focus:border-blue-500 focus:ring-blue-500 disabled:opacity-50 disabled:pointer-events-none dark:bg-neutral-900 dark:border-neutral-700 dark:text-neutral-400 dark:placeholder-neutral-500 dark:focus:ring-neutral-600"
                    placeholder="your@email.com"
                  />
                </div>

                <div>
                  <div class="flex justify-between items-center">
                    <label for="password" class="block text-sm mb-2 dark:text-white">Password</label>
                    <.link
                      href={~p"/users/reset_password"}
                      class="inline-flex items-center gap-x-1 text-sm text-blue-600 decoration-2 hover:underline focus:outline-none focus:underline font-medium dark:text-blue-500"
                    >
                      Forgot password?
                    </.link>
                  </div>
                  <div class="relative">
                    <.input
                      field={@form[:password]}
                      type="password"
                      label=""
                      required
                      class="py-3 px-4 block w-full border-gray-200 rounded-lg text-sm focus:border-blue-500 focus:ring-blue-500 disabled:opacity-50 disabled:pointer-events-none dark:bg-neutral-900 dark:border-neutral-700 dark:text-neutral-400 dark:placeholder-neutral-500 dark:focus:ring-neutral-600"
                      placeholder="••••••••"
                    />
                  </div>
                </div>

                <div class="flex items-center">
                  <div class="flex">
                    <.input
                      field={@form[:remember_me]}
                      type="checkbox"
                      label="Remember me"
                      class="shrink-0 mt-0.5 border-gray-200 rounded text-blue-600 focus:ring-blue-500 dark:bg-neutral-800 dark:border-neutral-700 dark:checked:bg-blue-500 dark:checked:border-blue-500 dark:focus:ring-offset-gray-800"
                    />
                  </div>
                </div>

                <:actions>
                  <.button
                    phx-disable-with="Signing in..."
                    class="w-full py-3 px-4 inline-flex justify-center items-center gap-x-2 text-sm font-medium rounded-lg border border-transparent bg-blue-600 text-white hover:bg-blue-700 focus:outline-none focus:bg-blue-700 disabled:opacity-50 disabled:pointer-events-none"
                  >
                    Sign in
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
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form, page_title: "Log in"), temporary_assigns: [form: form]}
  end
end
