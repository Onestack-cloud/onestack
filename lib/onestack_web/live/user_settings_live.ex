defmodule OnestackWeb.UserSettingsLive do
  use OnestackWeb, :live_view

  alias Onestack.{Accounts, Subscriptions}

  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <!-- Header -->
      <div class="mb-8">
        <div class="flex items-center space-x-4">
          <div class="flex-shrink-0">
            <div class="h-12 w-12 bg-gradient-to-r from-indigo-500 to-purple-600 rounded-lg flex items-center justify-center">
              <svg class="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
              </svg>
            </div>
          </div>
          <div>
            <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
              Account Settings
            </h1>
            <p class="mt-1 text-sm text-gray-600 dark:text-gray-400">
              Manage your account preferences, security, and billing information
            </p>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="grid grid-cols-1 lg:grid-cols-4 gap-8">
        <!-- Navigation Sidebar -->
        <div class="lg:col-span-1">
          <nav class="space-y-1">
            <a href="#profile" class="bg-indigo-50 border-indigo-500 text-indigo-700 hover:bg-indigo-50 hover:text-indigo-700 group border-l-4 px-3 py-2 flex items-center text-sm font-medium dark:bg-indigo-900/20 dark:border-indigo-400 dark:text-indigo-300">
              <svg class="text-indigo-500 mr-3 flex-shrink-0 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
              </svg>
              Profile
            </a>
            <a href="#security" class="border-transparent text-gray-900 hover:bg-gray-50 hover:text-gray-900 group border-l-4 px-3 py-2 flex items-center text-sm font-medium dark:text-gray-300 dark:hover:bg-gray-800">
              <svg class="text-gray-400 group-hover:text-gray-500 mr-3 flex-shrink-0 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
              </svg>
              Security
            </a>
            <a href="#billing" class="border-transparent text-gray-900 hover:bg-gray-50 hover:text-gray-900 group border-l-4 px-3 py-2 flex items-center text-sm font-medium dark:text-gray-300 dark:hover:bg-gray-800">
              <svg class="text-gray-400 group-hover:text-gray-500 mr-3 flex-shrink-0 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
              </svg>
              Billing & Subscription
            </a>
          </nav>
        </div>

        <!-- Content Area -->
        <div class="lg:col-span-3 space-y-8">
            
            <!-- Profile Section -->
            <div id="profile" class="bg-white dark:bg-gray-800 shadow rounded-lg">
              <div class="px-6 py-5 border-b border-gray-200 dark:border-gray-700">
                <h3 class="text-lg font-medium text-gray-900 dark:text-white">
                  Profile Information
                </h3>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  Update your personal information and email address.
                </p>
              </div>
              <div class="px-6 py-5">
                <!-- Current Email Display -->
                <div class="mb-6">
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Current Email Address
                  </label>
                  <div class="flex items-center p-3 bg-gray-50 dark:bg-gray-700 rounded-md">
                    <svg class="h-5 w-5 text-gray-400 mr-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 12a4 4 0 10-8 0 4 4 0 008 0zm0 0v1.5a2.5 2.5 0 005 0V12a9 9 0 10-9 9m4.5-1.206a8.959 8.959 0 01-4.5 1.207" />
                    </svg>
                    <span class="text-sm font-medium text-gray-900 dark:text-white">
                      <%= @current_email %>
                    </span>
                  </div>
                </div>

                <!-- Change Email Form -->
                <div class="border-t border-gray-200 dark:border-gray-700 pt-6">
                  <h4 class="text-sm font-medium text-gray-900 dark:text-white mb-4">
                    Change Email Address
                  </h4>
                  <.form
                    for={@email_form}
                    id="email_form"
                    phx-submit="update_email"
                    phx-change="validate_email"
                    class="space-y-4"
                  >
                    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                          New Email Address
                        </label>
                        <.input
                          field={@email_form[:email]}
                          type="email"
                          placeholder="Enter your new email"
                          required
                          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                          Current Password
                        </label>
                        <.input
                          name="current_password"
                          id="current_password_for_email"
                          type="password"
                          value={@email_form_current_password}
                          placeholder="Confirm with password"
                          required
                          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                        />
                      </div>
                    </div>
                    <div class="flex justify-end">
                      <.button
                        phx-disable-with="Sending verification..."
                        class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                      >
                        Send Verification Email
                      </.button>
                    </div>
                  </.form>
                </div>
              </div>
            </div>

            <!-- Security Section -->
            <div id="security" class="bg-white dark:bg-gray-800 shadow rounded-lg">
              <div class="px-6 py-5 border-b border-gray-200 dark:border-gray-700">
                <h3 class="text-lg font-medium text-gray-900 dark:text-white">
                  Security Settings
                </h3>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  Manage your password and account security.
                </p>
              </div>
              <div class="px-6 py-5">
                <div class="mb-6">
                  <div class="flex items-center p-3 bg-green-50 dark:bg-green-900/20 rounded-md border border-green-200 dark:border-green-800">
                    <svg class="h-5 w-5 text-green-400 mr-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    <div>
                      <p class="text-sm font-medium text-green-800 dark:text-green-200">
                        Password last updated: Recently
                      </p>
                      <p class="text-sm text-green-600 dark:text-green-400">
                        Your account is secure with strong password protection
                      </p>
                    </div>
                  </div>
                </div>

                <div class="border-t border-gray-200 dark:border-gray-700 pt-6">
                  <h4 class="text-sm font-medium text-gray-900 dark:text-white mb-4">
                    Update Password
                  </h4>
                  <.form
                    for={@password_form}
                    id="password_form"
                    phx-submit="update_password"
                    phx-change="validate_password"
                    class="space-y-4"
                  >
                    <div class="grid grid-cols-1 gap-4">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                          New Password
                        </label>
                        <.input
                          field={@password_form[:password]}
                          type="password"
                          placeholder="Enter new password"
                          required
                          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                          Confirm New Password
                        </label>
                        <.input
                          field={@password_form[:password_confirmation]}
                          type="password"
                          placeholder="Confirm new password"
                          required
                          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                          Current Password
                        </label>
                        <.input
                          name="current_password"
                          id="current_password_for_password"
                          type="password"
                          value={@current_password}
                          placeholder="Enter current password"
                          required
                          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                        />
                      </div>
                    </div>
                    <div class="flex justify-end">
                      <.button
                        phx-disable-with="Updating..."
                        class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                      >
                        Update Password
                      </.button>
                    </div>
                  </.form>
                </div>
              </div>
            </div>

            <!-- Billing & Subscription Section -->
            <div id="billing" class="bg-white dark:bg-gray-800 shadow rounded-lg">
              <div class="px-6 py-5 border-b border-gray-200 dark:border-gray-700">
                <h3 class="text-lg font-medium text-gray-900 dark:text-white">
                  Billing & Subscription
                </h3>
                <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
                  Manage your subscription plan and billing information.
                </p>
              </div>
              <div class="px-6 py-5">
                <%= if @subscription do %>
                  <!-- Current Subscription -->
                  <div class="mb-6">
                    <div class="flex items-center justify-between p-4 bg-gradient-to-r from-indigo-50 to-purple-50 dark:from-indigo-900/20 dark:to-purple-900/20 rounded-lg border border-indigo-200 dark:border-indigo-800">
                      <div class="flex items-center space-x-3">
                        <div class="h-10 w-10 bg-gradient-to-r from-indigo-500 to-purple-600 rounded-lg flex items-center justify-center">
                          <svg class="h-5 w-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
                          </svg>
                        </div>
                        <div>
                          <h4 class="text-lg font-semibold text-gray-900 dark:text-white">
                            <%= String.capitalize(@subscription.plan_type) %> Plan
                          </h4>
                          <p class="text-sm text-gray-600 dark:text-gray-400">
                            Status: <span class="font-medium capitalize text-green-600 dark:text-green-400"><%= @subscription.status %></span>
                          </p>
                        </div>
                      </div>
                      <div class="text-right">
                        <div class="text-sm text-gray-600 dark:text-gray-400 space-y-1">
                          <%= if @subscription.plan_type == "team" do %>
                            <div class="flex items-center">
                              <svg class="h-4 w-4 text-gray-400 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM9 9a2 2 0 11-4 0 2 2 0 014 0z" />
                              </svg>
                              <%= @subscription.num_users %> users
                            </div>
                          <% end %>
                          <div class="flex items-center">
                            <svg class="h-4 w-4 text-gray-400 mr-1" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                            </svg>
                            <%= length(@subscription.selected_products) %> products
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <%= if @subscription.status == "active" do %>
                    <!-- Danger Zone -->
                    <div class="border-t border-gray-200 dark:border-gray-700 pt-6">
                      <div class="border border-red-200 dark:border-red-800 rounded-lg p-6 bg-red-50 dark:bg-red-900/20">
                        <div class="flex items-start">
                          <div class="flex-shrink-0">
                            <svg class="h-6 w-6 text-red-600 dark:text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.082 16.5c-.77.833.192 2.5 1.732 2.5z" />
                            </svg>
                          </div>
                          <div class="ml-4 flex-1">
                            <h4 class="text-lg font-medium text-red-900 dark:text-red-200">
                              Cancel Subscription
                            </h4>
                            <p class="mt-2 text-sm text-red-700 dark:text-red-300">
                              Permanently cancel your subscription and immediately lose access to all products. This action cannot be undone and will delete all your team data.
                            </p>
                            <div class="mt-4">
                              <button
                                phx-click="open_cancel_modal"
                                class="inline-flex items-center px-4 py-2 border border-red-600 text-sm font-medium rounded-md text-red-700 bg-white hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 dark:bg-red-900/50 dark:text-red-200 dark:border-red-700 dark:hover:bg-red-900/70"
                              >
                                <svg class="mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                                </svg>
                                Cancel Subscription
                              </button>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  <% else %>
                    <!-- Canceled Subscription Info -->
                    <div class="border-t border-gray-200 dark:border-gray-700 pt-6">
                      <div class="text-center p-6 bg-gray-50 dark:bg-gray-700 rounded-lg">
                        <svg class="mx-auto h-12 w-12 text-gray-400 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728L5.636 5.636m12.728 12.728L18.364 5.636M5.636 18.364l12.728-12.728" />
                        </svg>
                        <h4 class="text-lg font-medium text-gray-900 dark:text-white">
                          Subscription <%= String.capitalize(@subscription.status) %>
                        </h4>
                        <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
                          Your subscription is currently <%= @subscription.status %> and you no longer have access to products.
                        </p>
                      </div>
                    </div>
                  <% end %>
                <% else %>
                  <!-- No Subscription -->
                  <div class="text-center py-8">
                    <svg class="mx-auto h-16 w-16 text-gray-400 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1" />
                    </svg>
                    <h3 class="text-xl font-medium text-gray-900 dark:text-white mb-2">
                      No Active Subscription
                    </h3>
                    <p class="text-sm text-gray-600 dark:text-gray-400 mb-6">
                      Start your journey with Onestack by choosing a subscription plan that fits your needs.
                    </p>
                    <a
                      href="/onboarding"
                      class="inline-flex items-center px-6 py-3 border border-transparent text-base font-medium rounded-md shadow-sm text-white bg-gradient-to-r from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
                    >
                      <svg class="mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                      </svg>
                      Get Started
                    </a>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Cancel Subscription Modal -->
      <.modal :if={@show_cancel_modal} id="cancel-subscription-modal" show on_cancel={JS.push("close_cancel_modal")}>
        <div class="text-center">
          <div class="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-red-100 dark:bg-red-900/20">
            <svg class="h-8 w-8 text-red-600 dark:text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.082 16.5c-.77.833.192 2.5 1.732 2.5z" />
            </svg>
          </div>
          <div class="mt-4">
            <h3 class="text-lg font-medium text-gray-900 dark:text-white">Cancel Subscription</h3>
            <div class="mt-2">
              <p class="text-sm text-gray-600 dark:text-gray-400">
                Are you absolutely sure you want to cancel your subscription?
              </p>
            </div>
            <div class="mt-4 p-4 bg-red-50 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800">
              <div class="text-sm text-red-800 dark:text-red-200">
                <p class="font-semibold mb-2">⚠️ This action will:</p>
                <ul class="text-left space-y-1">
                  <li>• Immediately remove access to ALL products</li>
                  <li>• Delete ALL team data permanently</li>
                  <li>• Cancel billing immediately</li>
                </ul>
                <p class="font-semibold mt-3 text-center">This action CANNOT be undone.</p>
              </div>
            </div>
          </div>
        </div>
        <div class="mt-6 flex items-center justify-end space-x-3">
          <button
            phx-click="close_cancel_modal"
            type="button"
            class="inline-flex items-center px-4 py-2 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 dark:bg-gray-700 dark:text-gray-300 dark:border-gray-600 dark:hover:bg-gray-600"
          >
            Cancel
          </button>
          <button
            phx-click="cancel_subscription"
            type="button"
            class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
          >
            <%= if @canceling_subscription do %>
              <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Canceling...
            <% else %>
              Yes, Cancel Subscription
            <% end %>
          </button>
        </div>
      </.modal>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    
    # Load subscription data
    subscription = Subscriptions.get_subscription_by_email(user.email)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:subscription, subscription)
      |> assign(:canceling_subscription, false)
      |> assign(:show_cancel_modal, false)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end

  def handle_event("open_cancel_modal", _params, socket) do
    {:noreply, assign(socket, :show_cancel_modal, true)}
  end

  def handle_event("close_cancel_modal", _params, socket) do
    {:noreply, assign(socket, :show_cancel_modal, false)}
  end

  def handle_event("cancel_subscription", _params, socket) do
    subscription = socket.assigns.subscription

    case subscription do
      nil ->
        {:noreply, put_flash(socket, :error, "No active subscription to cancel.")}

      %{stripe_subscription_id: stripe_subscription_id} ->
        # Set loading state
        socket = assign(socket, :canceling_subscription, true)

        # Cancel the Stripe subscription
        case Stripe.Subscription.cancel(stripe_subscription_id) do
          {:ok, _canceled_subscription} ->
            # Update our local subscription record
            case Subscriptions.update_subscription_status(stripe_subscription_id, "canceled") do
              {:ok, updated_subscription} ->
                # Also remove all products from the user's team
                user_email = socket.assigns.current_user.email
                case Onestack.Teams.remove_all_products_for_admin(user_email) do
                  {:ok, _updated_team} ->
                    {:noreply,
                     socket
                     |> assign(:subscription, updated_subscription)
                     |> assign(:canceling_subscription, false)
                     |> assign(:show_cancel_modal, false)
                     |> put_flash(:info, "Your subscription has been successfully canceled. You will lose access to all products immediately.")}
                     
                  {:error, _reason} ->
                    {:noreply,
                     socket
                     |> assign(:subscription, updated_subscription)
                     |> assign(:canceling_subscription, false)
                     |> assign(:show_cancel_modal, false)
                     |> put_flash(:warning, "Subscription was canceled but there was an issue removing product access. Please contact support if you still see products.")}
                end

              {:error, _reason} ->
                {:noreply,
                 socket
                 |> assign(:canceling_subscription, false)
                 |> assign(:show_cancel_modal, false)
                 |> put_flash(:error, "Subscription was canceled in Stripe but failed to update locally. Please contact support.")}
            end

          {:error, %Stripe.Error{message: message}} ->
            {:noreply,
             socket
             |> assign(:canceling_subscription, false)
             |> assign(:show_cancel_modal, false)
             |> put_flash(:error, "Failed to cancel subscription: #{message}")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:canceling_subscription, false)
             |> assign(:show_cancel_modal, false)
             |> put_flash(:error, "Failed to cancel subscription. Please try again or contact support.")}
        end
    end
  end
end