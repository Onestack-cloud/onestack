defmodule OnestackWeb.UserLoginLive do
  use OnestackWeb, :live_view

  def render(assigns) do
    ~H"""
    <section id="log_in" class="">
      <div class="flex flex-col items-center mt-20 px-6 py-8 mx-auto md:h-screen lg:py-0">
        <div class="w-full bg-white dark:bg-gray-800 rounded-lg shadow dark:border md:mt-0 sm:max-w-md xl:p-0  dark:border-gray-700">
          <div class="p-6 space-y-4 md:space-y-6 sm:p-8">
            <div class="text-center">
              <h1 class="text-xl font-bold leading-tight tracking-tight text-gray-900 md:text-2xl dark:text-white">
                Sign in
              </h1>
              <p class="text-sm font-light text-gray-500 dark:text-gray-400">
                Don't have an account yet?
                <.link
                  navigate={~p"/users/register"}
                  class="font-medium text-primary-600 hover:underline dark:text-primary-500"
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
                class="space-y-4 md:space-y-6"
              >
                <div>
                  <.input
                    field={@form[:email]}
                    type="email"
                    label="Email address"
                    required
                    class="bg-gray-50 border border-gray-300 text-gray-900 rounded-lg focus:ring-primary-600 focus:border-primary-600 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
                    placeholder="your@email.com"
                    autocomplete="username"
                  />
                </div>

                <div>
                  <div class="flex justify-between items-center">
                    <label
                      for="current-password"
                      class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
                    >
                      Password
                    </label>
                    <.link
                      href={~p"/users/reset_password"}
                      class="text-sm font-medium text-primary-600 hover:underline dark:text-white"
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
                      class="bg-gray-50 border border-gray-300 text-gray-900 rounded-lg focus:ring-primary-600 focus:border-primary-600 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
                      placeholder="••••••••"
                    />
                  </div>
                </div>

                <div class="flex items-center justify-between">
                  <div class="flex items-start">
                    <div class="flex items-center h-5">
                      <.input
                        field={@form[:remember_me]}
                        type="checkbox"
                        label=""
                      />
                    </div>
                    <div class="flex items-center text-md">
                      <label
                        for="remember"
                        class="ms-2 text-sm font-medium text-gray-900 dark:text-gray-300"
                      >
                        Remember me
                      </label>
                    </div>
                  </div>
                </div>

                <:actions>
                  <.button
                    phx-disable-with="Signing in..."
                    class="w-full text-white bg-primary-600 hover:bg-primary-700 focus:ring-4 focus:outline-none focus:ring-primary-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center dark:bg-primary-600 dark:hover:bg-primary-700 dark:focus:ring-primary-800"
                  >
                    Sign in
                  </.button>
                </:actions>
              </.simple_form>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form, page_title: "Log in"), temporary_assigns: [form: form]}
  end
end
