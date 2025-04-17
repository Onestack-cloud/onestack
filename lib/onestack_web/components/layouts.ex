defmodule OnestackWeb.Layouts do
  use OnestackWeb, :html

  defp is_admin?(assigns) do
    teams = Onestack.Teams.list_teams()
    Enum.any?(teams, fn team -> team.admin_email == assigns.current_user.email end)
  end

  embed_templates "layouts/*"

  def sidebar_live(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 dark:bg-slate-900 flex flex-col md:flex-row">
      <!-- Mobile Navigation Toggle - Only visible on mobile -->
      <div class="md:hidden p-2 border-b border-gray-200 dark:border-gray-700">
        <button
          type="button"
          data-drawer-target="sidebar-menu"
          data-drawer-toggle="sidebar-menu"
          aria-controls="sidebar-menu"
          class="inline-flex items-center p-2 text-gray-500 rounded-lg hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-gray-200 dark:text-gray-400 dark:hover:bg-gray-700 dark:focus:ring-gray-600"
        >
          <span class="sr-only">Open sidebar</span>
          <svg
            class="w-6 h-6"
            aria-hidden="true"
            fill="currentColor"
            viewBox="0 0 20 20"
            xmlns="http://www.w3.org/2000/svg"
          >
            <path
              clip-rule="evenodd"
              fill-rule="evenodd"
              d="M2 4.75A.75.75 0 012.75 4h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 4.75zm0 10.5a.75.75 0 01.75-.75h7.5a.75.75 0 010 1.5h-7.5a.75.75 0 01-.75-.75zM2 10a.75.75 0 01.75-.75h14.5a.75.75 0 010 1.5H2.75A.75.75 0 012 10z"
            >
            </path>
          </svg>
        </button>
      </div>

      <!-- Sidebar -->
      <aside
        id="sidebar-menu"
        class="fixed top-0 left-0 z-40 h-screen w-64 transform -translate-x-full transition-transform md:translate-x-0 md:relative md:w-64 flex-shrink-0"
        aria-label="Sidebar"
      >
        <div class="h-full overflow-y-auto flex flex-col bg-white border-r border-gray-200 dark:bg-gray-800 dark:border-gray-700">
          <!-- Header with close button for mobile -->
          <div class="flex justify-between items-center">
            <button
              type="button"
              data-drawer-hide="sidebar-menu"
              aria-controls="sidebar-menu"
              class="md:hidden p-1 text-gray-500 rounded-lg hover:bg-gray-100 focus:ring-2 focus:ring-gray-200 dark:text-gray-400 dark:hover:bg-gray-700 dark:focus:ring-gray-600"
            >
              <span class="sr-only">Close sidebar</span>
              <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
                <path
                  fill-rule="evenodd"
                  d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
                  clip-rule="evenodd"
                ></path>
              </svg>
            </button>
          </div>

          <!-- Navigation -->
          <div class="flex-1 px-3 py-4 overflow-y-auto">
            <ul class="space-y-2">
              <%= if is_admin?(assigns) do %>
                <!-- Dashboard -->
                <li>
                  <span class="flex items-center p-2 text-gray-400 rounded-lg dark:text-gray-500 group cursor-not-allowed">
                    <svg
                      class="w-5 h-5 text-gray-400 dark:text-gray-500"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
                      />
                    </svg>
                    <span class="ml-3">Dashboard</span>
                    <span class="ml-auto inline-flex items-center justify-center px-2 py-0.5 text-xs font-medium text-gray-500 bg-gray-200 rounded dark:bg-gray-700 dark:text-gray-400">
                      Coming Soon
                    </span>
                  </span>
                </li>
                <!-- Users Dropdown -->
                <li>
                  <.link
                    navigate={~p"/admin/teams"}
                    class={[
                      "flex items-center w-full p-2 text-base transition duration-75 rounded-lg group",
                      String.contains?(
                        @current_path,
                        "/admin/teams"
                      ) &&
                        "bg-gray-100 dark:bg-gray-700 text-blue-600 dark:text-blue-400",
                      !String.contains?(
                        @current_path,
                        "/admin/teams"
                      ) &&
                        "text-gray-900 dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700"
                    ]}
                  >
                    <svg
                      class="w-5 h-5 text-gray-500 dark:text-gray-400"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
                      />
                    </svg>
                    <span class="flex-1 ml-3 text-left whitespace-nowrap">
                      Team
                    </span>
                  </.link>
                </li>
                <!-- Features -->
                <li>
                  <.link
                    navigate={~p"/admin/features"}
                    class={[
                      "flex items-center w-full p-2 text-base transition duration-75 rounded-lg group",
                      String.contains?(
                        @current_path,
                        "/admin/features"
                      ) &&
                        "bg-gray-100 dark:bg-gray-700 text-blue-600 dark:text-blue-400",
                      !String.contains?(
                        @current_path,
                        "/admin/features"
                      ) &&
                        "text-gray-900 dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700"
                    ]}
                  >
                    <Lucide.render
                      icon="layers"
                      class={[
                        "w-5 h-5",
                        String.contains?(
                          @current_path,
                          "/admin/features"
                        ) &&
                          "text-blue-600 dark:text-blue-400",
                        !String.contains?(
                          @current_path,
                          "/admin/features"
                        ) &&
                          "text-gray-500 dark:text-gray-400"
                      ]}
                    />
                    <span class="flex-1 ml-3 text-left whitespace-nowrap">
                      Features
                    </span>
                  </.link>
                </li>
                <!-- Billing -->
                <li>
                  <a
                    href="https://billing.stripe.com/p/login/3cs28t1PmcYZ0OQ9AA"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="flex items-center p-2 text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group"
                  >
                    <Lucide.render
                      icon="credit-card"
                      class="w-5 h-5 text-gray-500 dark:text-gray-400"
                    />
                    <span class="flex-1 ml-3 whitespace-nowrap">
                      Billing
                    </span>
                    <span class="inline-flex items-center justify-center px-2 ml-3 text-sm font-medium text-gray-800 bg-gray-200 rounded-full dark:bg-gray-700 dark:text-gray-300">
                      New
                    </span>
                    <svg
                      class="w-4 h-4 ml-2"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                      xmlns="http://www.w3.org/2000/svg"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                      >
                      </path>
                    </svg>
                  </a>
                </li>
                <!-- <li>
                  <a
                    href="#"
                    class="flex items-center w-full p-2 text-base text-gray-900 transition duration-75 rounded-lg group hover:bg-gray-100 dark:text-white dark:hover:bg-gray-700"
                  >
                    <Lucide.render
                      icon="trophy"
                      class="w-5 h-5 text-gray-500 dark:text-gray-400"
                    />
                    <span class="flex-1 ml-3 text-left whitespace-nowrap">
                      Become an affiliate
                    </span>
                  </a>
                </li> -->
              <% else %>
                <!-- Member-only navigation items -->
                <li>
                  <.link
                    navigate={~p"/member/features"}
                    class={[
                      "flex items-center w-full p-2 text-base transition duration-75 rounded-lg group",
                      String.contains?(
                        @current_path,
                        "/member/features"
                      ) &&
                        "bg-gray-100 dark:bg-gray-700 text-blue-600 dark:text-blue-400",
                      !String.contains?(
                        @current_path,
                        "/member/features"
                      ) &&
                        "text-gray-900 dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700"
                    ]}
                  >
                    <Lucide.render
                      icon="layers"
                      class={[
                        "w-5 h-5",
                        String.contains?(
                          @current_path,
                          "/member/features"
                        ) &&
                          "text-blue-600 dark:text-blue-400",
                        !String.contains?(
                          @current_path,
                          "/member/features"
                        ) &&
                          "text-gray-500 dark:text-gray-400"
                      ]}
                    />
                    <span class="flex-1 ml-3 text-left whitespace-nowrap">
                      Features
                    </span>
                  </.link>
                </li>
              <% end %>
            </ul>
          </div>
          <!-- Footer -->
      <!-- Support and Feedback Links -->
          <div class="px-3 py-4">
            <ul class="space-y-2 text-sm">
              <li>
                <a
                  href={OnestackWeb.URLHelper.subdomain_url("support")}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="flex items-center p-2 text-gray-600 rounded-lg hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700 group"
                >
                  <svg
                    class="w-5 h-5"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M18.364 5.636l-3.536 3.536m0 5.656l3.536 3.536M9.172 9.172L5.636 5.636m3.536 9.192l-3.536 3.536M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-5 0a4 4 0 11-8 0 4 4 0 018 0z"
                    />
                  </svg>
                  <span class="ml-3">Support</span>
                  <svg
                    class="w-4 h-4 ml-2"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    xmlns="http://www.w3.org/2000/svg"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                    />
                  </svg>
                </a>
              </li>
              <li>
                <a
                  href="https://community.onestack.cloud"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="flex items-center p-2 text-gray-600 rounded-lg hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700 group"
                >
                  <svg
                    class="w-5 h-5"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M17 8h2a2 2 0 012 2v6a2 2 0 01-2 2h-2v4l-4-4H9a1.994 1.994 0 01-1.414-.586m0 0L11 14h4a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2v4l.586-.586z"
                    />
                  </svg>
                  <span class="ml-3">Community</span>
                  <svg
                    class="w-4 h-4 ml-2"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    xmlns="http://www.w3.org/2000/svg"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                    />
                  </svg>
                </a>
              </li>
              <li>
                <a
                  href="https://docs.onestack.cloud"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="flex items-center p-2 text-gray-600 rounded-lg hover:bg-gray-100 dark:text-gray-400 dark:hover:bg-gray-700 group"
                >
                  <Lucide.render icon="book-open-text" class="w-5 h-5" />

                  <span class="ml-3">Docs</span>
                  <svg
                    class="w-4 h-4 ml-2"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    xmlns="http://www.w3.org/2000/svg"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                    />
                  </svg>
                </a>
              </li>
            </ul>
          </div>

          <div class="border-t border-gray-200 p-4 dark:border-gray-700">
            <div class="flex items-center">
              <button
                type="button"
                class="flex items-center w-full p-2 text-base text-gray-900 transition duration-75 rounded-lg group hover:bg-gray-100 dark:text-white dark:hover:bg-gray-700 hover:cursor-pointer"
                data-dropdown-toggle="user-dropdown"
              >
                <img
                  class="w-6 h-6 rounded-full hidden dark:block"
                  src="/images/logo_white.png"
                  alt="user photo"
                />
                <img
                  class="w-6 h-6 rounded-full dark:hidden"
                  src="/images/logo_black.png"
                  alt="user photo"
                />
                <span class="ml-3">
                  <%= if @current_user.first_name && @current_user.last_name do %>
                    <%= @current_user.first_name %> <%= @current_user.last_name %>
                  <% else %>
                    <%= @current_user.email %>
                  <% end %>
                </span>
                <Lucide.render
                  icon="chevron-down"
                  class="w-6 h-6 ml-auto"
                />
              </button>
            </div>
            <!-- User dropdown menu -->
            <div
              id="user-dropdown"
              class="z-10 hidden bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600"
            >
              <ul class="py-2 text-sm text-gray-700 dark:text-gray-200">
                <li>
                  <.link
                    navigate={~p"/users/settings"}
                    class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                  >
                    Account settings
                  </.link>
                </li>
                <li>
                  <.link
                    href={~p"/users/log_out"}
                    method="delete"
                    class="block px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                  >
                    Log out
                  </.link>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </aside>

      <!-- Main Content -->
      <main class="w-full min-h-screen">
        <%= @inner_content %>
      </main>
    </div>
    """
  end

  def topbar_live(assigns) do
    ~H"""
    <header class="flex flex-wrap lg:justify-start lg:flex-nowrap z-50 w-full bg-white border-b border-gray-200 dark:bg-gray-900 dark:border-neutral-700">
      <nav class="relative max-w-[85rem] w-full mx-auto lg:flex lg:items-center lg:justify-between lg:gap-3 py-2 px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between items-center gap-x-1 me-6">
          <a class="flex-none" href={OnestackWeb.URLHelper.main_domain()}>
            <img
              src="/images/logo_black_text.png"
              alt="Logo"
              class="h-6 object-contain dark:hidden"
            />
            <img
              src="/images/logo_white_text.png"
              alt="Logo"
              class="h-6 object-contain hidden dark:block"
            />
            <p class="text-[0.625rem] lg:text-xs flex justify-end text-black dark:text-white">
              Powered by open source
            </p>
          </a>

          <!-- Mobile: Action buttons next to toggle -->
          <div class="flex items-center lg:hidden gap-2">
            <%= if @current_user do %>
              <a
                href={OnestackWeb.URLHelper.subdomain_url("app")}
                class="inline-flex items-center font-medium text-sm rounded-lg bg-blue-600 text-white hover:bg-blue-700 focus:outline-none focus:bg-blue-700 disabled:opacity-50 disabled:pointer-events-none dark:bg-blue-500 dark:hover:bg-blue-600 dark:focus:bg-blue-600 px-2 py-2"
              >
                My Stack
              </a>
            <% else %>
              <.link
                navigate={~p"/users/register"}
                class="text-white bg-gradient-to-r from-blue-500 via-blue-600 to-blue-700
                hover:bg-gradient-to-br focus:ring-4 focus:outline-none focus:ring-blue-300
                dark:focus:ring-blue-800 font-medium rounded-lg text-sm px-2 py-2
                text-center border border-blue-800 shadow-[0_4px_6px_-1px_rgba(0,0,0,0.2)]
                transition-all duration-200 relative"
              >
                Get started
              </.link>
            <% end %>

            <!-- Collapse Button -->
            <button
              type="button"
              class="hs-collapse-toggle relative size-9 flex justify-center items-center font-medium text-[12px] rounded-lg border border-gray-200 text-gray-800 hover:bg-gray-100 focus:outline-none focus:bg-gray-100 disabled:opacity-50 disabled:pointer-events-none dark:text-white dark:border-neutral-700 dark:hover:bg-neutral-700 dark:focus:bg-neutral-700"
              id="hs-header-base-collapse"
              aria-expanded="false"
              aria-controls="hs-header-base"
              aria-label="Toggle navigation"
              data-hs-collapse="#hs-header-base"
            >
              <svg
                class="hs-collapse-open:hidden size-4"
                xmlns="http://www.w3.org/2000/svg"
                width="24"
                height="24"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <line x1="3" x2="21" y1="6" y2="6" /><line
                  x1="3"
                  x2="21"
                  y1="12"
                  y2="12"
                /><line x1="3" x2="21" y1="18" y2="18" />
              </svg>
              <svg
                class="hs-collapse-open:block shrink-0 hidden size-4"
                xmlns="http://www.w3.org/2000/svg"
                width="24"
                height="24"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M18 6 6 18" /><path d="m6 6 12 12" />
              </svg>
            </button>
          </div>
        </div>
        <!-- Collapse -->
        <div
          id="hs-header-base"
          class="hs-collapse hidden overflow-hidden transition-all duration-300 basis-full grow lg:block"
        >
          <div class="overflow-hidden overflow-y-auto max-h-[75vh] [&::-webkit-scrollbar]:w-2 [&::-webkit-scrollbar-thumb]:rounded-full [&::-webkit-scrollbar-track]:bg-gray-100 [&::-webkit-scrollbar-thumb]:bg-gray-300 dark:[&::-webkit-scrollbar-track]:bg-neutral-700 dark:[&::-webkit-scrollbar-thumb]:bg-neutral-500">
            <div class="py-2 lg:py-0 flex flex-col lg:flex-row lg:items-center gap-0.5 lg:gap-1">
              <div class="grow">
                <div class="flex flex-col lg:flex-row lg:items-center gap-0.5 lg:gap-3">
                  <a
                    class="p-2 flex items-center text-sm text-gray-800 hover:bg-gray-100 rounded-lg focus:outline-none focus:bg-gray-100 dark:text-neutral-200 dark:hover:bg-neutral-700 dark:focus:bg-neutral-700"
                    href={
                      OnestackWeb.URLHelper.main_domain_path("/features")
                    }
                  >
                    Features
                  </a>
                  <.link
                    class="p-2 flex items-center text-sm text-gray-800 hover:bg-gray-100 rounded-lg focus:outline-none focus:bg-gray-100 dark:text-neutral-200 dark:hover:bg-neutral-700 dark:focus:bg-neutral-700"
                    navigate={
                      OnestackWeb.URLHelper.main_domain_path("/pricing")
                    }
                  >
                    Pricing
                  </.link>
                  <.link
                    href="https://docs.onestack.cloud"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="p-2 flex items-center text-sm text-gray-800 hover:bg-gray-100 rounded-lg focus:outline-none focus:bg-gray-100 dark:text-neutral-200 dark:hover:bg-neutral-700 dark:focus:bg-neutral-700"
                  >
                    Docs
                  </.link>
                  <.link
                    class="p-2 flex items-center text-sm text-gray-800 hover:bg-gray-100 rounded-lg focus:outline-none focus:bg-gray-100 dark:text-neutral-200 dark:hover:bg-neutral-700 dark:focus:bg-neutral-700"
                    navigate={
                      OnestackWeb.URLHelper.main_domain_path("/roadmap")
                    }
                  >
                    Roadmap
                  </.link>
                  <a
                    class="p-2 flex items-center text-sm text-gray-800 hover:bg-gray-100 rounded-lg focus:outline-none focus:bg-gray-100 dark:text-neutral-200 dark:hover:bg-neutral-700 dark:focus:bg-neutral-700"
                    href={
                      OnestackWeb.URLHelper.subdomain_url("feedback")
                    }
                  >
                    Feature Suggestions
                  </a>
                </div>
              </div>
              <!-- Button Group - Hide in mobile view since we've moved these to the top bar -->
              <div class="lg:ms-auto mt-2 lg:mt-0 flex flex-wrap items-center gap-x-2 hidden lg:flex">
                <%= if @current_user do %>
                  <a
                    href={OnestackWeb.URLHelper.subdomain_url("app")}
                    class="p-2.5 inline-flex items-center font-medium text-sm rounded-lg bg-blue-600 text-white hover:bg-blue-700 focus:outline-none focus:bg-blue-700 disabled:opacity-50 disabled:pointer-events-none dark:bg-blue-500 dark:hover:bg-blue-600 dark:focus:bg-blue-600"
                  >
                    My Stack
                  </a>
                  <div class="flex items-center lg:order-2 space-x-3 lg:space-x-0 rtl:space-x-reverse">
                    <button
                      type="button"
                      class="p-2.5 inline-flex items-center font-medium text-sm rounded-lg border border-gray-200 bg-white text-gray-800 shadow-sm hover:bg-gray-50 disabled:opacity-50 disabled:pointer-events-none dark:bg-gray-800 dark:border-gray-700 dark:text-gray-200 dark:hover:bg-gray-700 hover:cursor-pointer"
                      id="user-menu-button"
                      aria-expanded="false"
                      data-dropdown-toggle="user-dropdown"
                      data-dropdown-placement="bottom"
                    >
                      <span class="sr-only">Open user menu</span>
                      <Lucide.render icon="User" class="w-5 h-5" />
                    </button>
                    <!-- Dropdown menu -->
                    <div
                      class="z-50 hidden my-4 text-base list-none bg-white divide-y divide-gray-100 rounded-lg shadow-sm dark:bg-gray-800 dark:divide-gray-700"
                      id="user-dropdown"
                    >
                      <div class="px-4 py-3">
                        <span class="block text-sm text-gray-900 dark:text-white">
                          <%= @current_user.first_name %> <%= @current_user.last_name %>
                        </span>
                        <span class="block text-sm text-gray-500 truncate dark:text-gray-400">
                          <%= @current_user.email %>
                        </span>
                      </div>
                      <ul class="py-2" aria-labelledby="user-menu-button">
                        <li>
                          <.link
                            href={
                              OnestackWeb.URLHelper.subdomain_url("app")
                            }
                            class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-white"
                          >
                            Dashboard
                          </.link>
                        </li>
                        <li>
                          <.link
                            navigate={~p"/users/settings"}
                            class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-white"
                          >
                            Settings
                          </.link>
                        </li>
                        <li>
                          <.link
                            href={~p"/users/log_out"}
                            method="delete"
                            class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700 dark:hover:text-white"
                          >
                            Log out
                          </.link>
                        </li>
                      </ul>
                    </div>
                  </div>
                <% else %>
                  <div class="flex items-center space-x-2">
                    <.link
                      navigate={~p"/users/log_in"}
                      class="text-gray-900 bg-white border border-gray-300 focus:outline-none hover:bg-gray-100 focus:ring-4 focus:ring-gray-100 font-medium rounded-lg text-sm px-3 py-2 dark:bg-gray-800 dark:text-white dark:border-gray-600 dark:hover:bg-gray-700 dark:hover:border-gray-600 dark:focus:ring-gray-700"
                    >
                      Login
                    </.link>
                    <.link
                      navigate={~p"/users/register"}
                      class="text-white bg-gradient-to-r from-blue-500 via-blue-600 to-blue-700
                      hover:bg-gradient-to-br focus:ring-4 focus:outline-none focus:ring-blue-300
                      dark:focus:ring-blue-800 font-medium rounded-lg text-sm px-3 py-2
                      text-center
                      border border-blue-800
                      shadow-[0_4px_6px_-1px_rgba(0,0,0,0.2)]
                      transition-all duration-200
                      relative
                      before:content-[''] before:absolute before:inset-0 before:rounded-lg
                      before:shadow-[inset_0_1px_2px_rgba(255,255,255,0.3)]
                      before:pointer-events-none
                      hover:translate-y-[1px] hover:shadow-[0_2px_4px_-1px_rgba(0,0,0,0.2)]
                      active:shadow-[inset_0_2px_4px_rgba(0,0,0,0.2)]"
                    >
                      Get started for free
                    </.link>
                  </div>
                <% end %>
              </div>
              <!-- End Button Group -->
            </div>
          </div>
        </div>
        <!-- End Collapse -->
      </nav>
    </header>

    <.flash_group flash={@flash} />
    <div class="relative min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 dark:from-gray-950 dark:to-gray-900 overflow-hidden">
      <div class="absolute inset-0">
        <svg
          class="w-full h-full opacity-10 dark:opacity-5 text-current dark:text-white"
          xmlns="http://www.w3.org/2000/svg"
        >
          <pattern
            id="grid"
            width="20"
            height="20"
            patternUnits="userSpaceOnUse"
          >
            <circle cx="2" cy="2" r="1.5" fill="currentColor" />
          </pattern>
          <rect width="100%" height="100%" fill="url(#grid)" />
        </svg>
      </div>
      <div class="relative z-[1] p-8">
        <%= @inner_content %>
      </div>
    </div>
    <!-- ========== FOOTER ========== -->
    <footer class="mt-auto bg-gray-100 w-full dark:bg-gray-900">
      <div class="mt-auto w-full max-w-[85rem] py-10 px-4 sm:px-6 lg:px-8 lg:pt-20 mx-auto">
        <!-- Grid -->
        <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-5 gap-6">
          <div class="col-span-full lg:col-span-1">
            <a
              class="flex-none"
              href={OnestackWeb.URLHelper.main_domain()}
            >
              <img
                src="/images/logo_black_text.png"
                alt="Logo"
                class="h-6 object-contain dark:hidden"
              />
              <img
                src="/images/logo_white_text.png"
                alt="Logo"
                class="h-6 object-contain hidden dark:block"
              />
              <p class="text-[0.625rem] lg:text-xs flex text-gray-600 dark:text-gray-400">
                Powered by open source
              </p>
            </a>
          </div>
          <!-- End Col -->
          <div class="col-span-1">
            <h4 class="font-semibold text-gray-900 dark:text-gray-100">
              Legal
            </h4>

            <div class="mt-3 grid space-y-3">
              <p>
                <a
                  class="inline-flex gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href={~p"/privacy"}
                >
                  Privacy policy
                </a>
              </p>
            </div>
          </div>
          <div class="col-span-1">
            <h4 class="font-semibold text-gray-900 dark:text-gray-100">
              Product
            </h4>

            <div class="mt-3 grid space-y-3">
              <p>
                <a
                  class="inline-flex gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href={~p"/privacy"}
                >
                  Pricing
                </a>
              </p>
              <p>
                <a
                  class="inline-flex gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href="#"
                >
                  Changelog
                </a>
              </p>
              <p>
                <a
                  class="inline-flex items-center gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href="https://docs.onestack.cloud"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Docs
                  <svg
                    class="w-3 h-3"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                    />
                  </svg>
                </a>
              </p>
              <p>
                <a
                  class="inline-flex items-center gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href="https://kuma.onestack.cloud/status/onestack"
                >
                  Status
                  <svg
                    class="w-3 h-3"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"
                    />
                  </svg>
                </a>
              </p>
              <p>
                <a
                  class="inline-flex gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href={
                    OnestackWeb.URLHelper.main_domain_path("/security")
                  }
                >
                  Security
                </a>
              </p>
            </div>
          </div>
          <!-- End Col -->
          <div class="col-span-1">
            <h4 class="font-semibold text-gray-900 dark:text-gray-100">
              Company
            </h4>

            <div class="mt-3 grid space-y-3">
              <p>
                <a
                  class="inline-flex gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href="mailto:founders@onestack.cloud"
                >
                  Email us
                </a>
              </p>
              <!-- <p>
                <a
                  class="inline-flex gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href="https://blog.onestack.cloud"
                >
                  Blog
                </a>
              </p>
              <p>
                <.link
                  navigate={~p"/about"}
                  class="inline-flex gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                >
                  About us
                </.link>
              </p>  -->
              <!-- <p>
                <a
                  class="inline-flex gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href="#"
                >
                  Careers
                </a>
                <span class="inline-block ms-1 text-xs bg-blue-700 text-white py-1 px-2 rounded-lg">
                  We're hiring
                </span>
              </p>
               <p>
                <a
                  class="inline-flex gap-x-2 text-gray-600 hover:text-gray-800 focus:outline-none focus:text-gray-800 dark:text-gray-400 dark:hover:text-gray-200 dark:focus:text-gray-200"
                  href="#"
                >
                  Customers
                </a>
              </p> -->
            </div>
          </div>
          <!-- End Col -->
        </div>
        <!-- End Grid -->
        <div class="mt-5 sm:mt-12 grid gap-y-2 sm:gap-y-0 sm:flex sm:justify-between sm:items-center">
          <div class="flex justify-between items-center">
            <p class="text-sm text-gray-500 dark:text-gray-400">
              © 2024-<%= DateTime.utc_now().year %> Onestack.
            </p>
          </div>
          <!-- End Col -->

          <!-- Social Brands -->
          <div>
            <a
              class="size-10 inline-flex justify-center items-center gap-x-2 text-sm font-semibold rounded-lg border border-gray-200 text-gray-500 hover:bg-gray-100 focus:outline-none focus:bg-gray-100 disabled:opacity-50 disabled:pointer-events-none dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-800 dark:focus:bg-gray-800"
              href="https://github.com/Onestack-cloud"
            >
              <Lucide.render icon="github" class="shrink-0 size-4" />
            </a>
            <a
              class="size-10 inline-flex justify-center items-center gap-x-2 text-sm font-semibold rounded-lg border border-gray-200 text-gray-500 hover:bg-gray-100 focus:outline-none focus:bg-gray-100 disabled:opacity-50 disabled:pointer-events-none dark:border-gray-700 dark:text-gray-400 dark:hover:bg-gray-800 dark:focus:bg-gray-800"
              href="https://linkedin.com/company/onestack-cloud"
            >
              <Lucide.render icon="linkedin" class="shrink-0 size-4" />
            </a>
          </div>
          <!-- End Social Brands -->
        </div>
      </div>
    </footer>
    <!-- ========== END FOOTER ========== -->
    """
  end
end
