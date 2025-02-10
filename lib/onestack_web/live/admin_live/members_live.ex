# lib/onestack_web/live/admin/members_live.ex
defmodule OnestackWeb.Admin.MembersLive do
  use OnestackWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to member updates
    end

    {:ok,
     assign(socket,
       page_title: "Team Members",
       members: get_dummy_members(),
       departments: get_dummy_departments(),
       roles: get_dummy_roles(),
       selected_department: "all",
       search: "",
       show_invite_modal: false,
       show_member_details: nil,
       view: "grid",
       stats: get_dummy_stats(),
       selected_members: MapSet.new(),
       show_bulk_actions: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-b from-gray-50 to-white dark:from-gray-900 dark:to-gray-800">
      <div class="px-4 sm:px-6 lg:px-8 py-8 w-full max-w-7xl mx-auto">
        <!-- Header with Stats -->
        <div class="mb-12">
          <div class="flex items-center justify-between mb-6">
            <div>
              <h1 class="text-4xl font-bold text-gray-900 dark:text-white">
                Team Members
              </h1>
              <p class="mt-2 text-lg text-gray-600 dark:text-gray-300">
                Manage your team and control product access
              </p>
            </div>
            <button
              class="inline-flex items-center gap-2 px-6 py-3 text-sm font-medium text-white bg-gradient-to-r from-blue-600 to-blue-700 rounded-full hover:from-blue-700 hover:to-blue-800 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-all duration-200 shadow-sm"
              phx-click="toggle-invite-modal"
            >
              <.icon name="hero-user-plus" class="w-4 h-4" />
              Invite Members
            </button>
          </div>

          <!-- Stats Cards -->
          <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mt-8">
            <%= for stat <- @stats do %>
              <div class="bg-white dark:bg-gray-800 rounded-2xl p-6 shadow-sm ring-1 ring-gray-200/50 dark:ring-gray-700/50">
                <div class="flex items-center justify-between">
                  <div>
                    <p class="text-sm font-medium text-gray-500 dark:text-gray-400">
                      <%= stat.label %>
                    </p>
                    <h3 class="mt-2 text-2xl font-bold text-gray-900 dark:text-white">
                      <%= stat.value %>
                    </h3>
                  </div>
                  <div class={[
                    "rounded-full p-3",
                    stat_background_color(stat.type)
                  ]}>
                    <.icon name={stat.icon} class={[
                      "w-5 h-5",
                      stat_icon_color(stat.type)
                    ]} />
                  </div>
                </div>
                <div class="mt-4 flex items-center gap-2 text-sm">
                  <.icon
                    name={if stat.trend > 0, do: "hero-arrow-up", else: "hero-arrow-down"}
                    class={[
                      "w-4 h-4",
                      if(stat.trend > 0, do: "text-green-500", else: "text-red-500")
                    ]}
                  />
                  <span class="text-gray-600 dark:text-gray-300">
                    <%= abs(stat.trend) %>% from last month
                  </span>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Filters and Search -->
        <div class="sticky top-0 z-10 bg-gray-50/80 dark:bg-gray-900/80 backdrop-blur-sm -mx-8 px-8 py-4 mb-6">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-4">
              <!-- View Toggle -->
              <div class="bg-white dark:bg-gray-800 rounded-lg p-1 flex items-center gap-1 shadow-sm">
                <button
                  class={[
                    "p-2 rounded-md transition-all duration-200",
                    @view == "grid" &&
                      "bg-blue-600 text-white",
                    @view != "grid" &&
                      "text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
                  ]}
                  phx-click="set-view"
                  phx-value-view="grid"
                >
                  <.icon name="hero-squares-2x2" class="w-5 h-5" />
                </button>
                <button
                  class={[
                    "p-2 rounded-md transition-all duration-200",
                    @view == "list" &&
                      "bg-blue-600 text-white",
                    @view != "list" &&
                      "text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-white"
                  ]}
                  phx-click="set-view"
                  phx-value-view="list"
                >
                  <.icon name="hero-list-bullet" class="w-5 h-5" />
                </button>
              </div>

              <!-- Department Filter -->
              <div class="flex items-center gap-2">
                <%= for department <- @departments do %>
                  <button
                    class={[
                      "px-4 py-2 text-sm font-medium rounded-full transition-all duration-200",
                      if(@selected_department == department.id,
                        do: "bg-blue-600 text-white",
                        else:
                          "bg-white text-gray-600 hover:bg-gray-100 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-gray-700"
                      )
                    ]}
                    phx-click="filter-department"
                    phx-value-department={department.id}
                  >
                    <%= department.name %>
                  </button>
                <% end %>
              </div>
            </div>

            <!-- Search -->
            <div class="relative">
              <input
                type="search"
                placeholder="Search members..."
                class="pl-10 pr-4 py-2.5 w-64 text-sm rounded-xl border-0 ring-1 ring-gray-200 focus:ring-2 focus:ring-blue-500 bg-white dark:bg-gray-800 dark:ring-gray-700 dark:focus:ring-blue-500"
                value={@search}
                phx-keyup="search"
                phx-debounce="300"
              />
              <.icon
                name="hero-magnifying-glass"
                class="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5"
              />
            </div>
          </div>

          <!-- Bulk Actions -->
          <%= if MapSet.size(@selected_members) > 0 do %>
            <div class="flex items-center justify-between mt-4 p-4 bg-blue-50 dark:bg-blue-900/30 rounded-xl">
              <div class="flex items-center gap-4">
                <span class="text-sm font-medium text-blue-700 dark:text-blue-300">
                  <%= MapSet.size(@selected_members) %> members selected
                </span>
                <div class="h-4 w-px bg-blue-200 dark:bg-blue-700"></div>
                <div class="flex items-center gap-2">
                  <button class="text-sm font-medium text-blue-700 dark:text-blue-300 hover:text-blue-800 dark:hover:text-blue-200">
                    Set Role
                  </button>
                  <button class="text-sm font-medium text-blue-700 dark:text-blue-300 hover:text-blue-800 dark:hover:text-blue-200">
                    Add to Department
                  </button>
                  <button class="text-sm font-medium text-red-600 dark:text-red-400 hover:text-red-700 dark:hover:text-red-300">
                    Remove Access
                  </button>
                </div>
              </div>
              <button
                class="text-sm font-medium text-blue-700 dark:text-blue-300 hover:text-blue-800 dark:hover:text-blue-200"
                phx-click="clear-selection"
              >
                Clear Selection
              </button>
            </div>
          <% end %>
        </div>

        <!-- Members Grid -->
        <%= if @view == "grid" do %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
            <%= for member <- @members do %>
              <div class={[
                "group relative bg-white dark:bg-gray-800 rounded-2xl shadow-sm ring-1 transition-all duration-200",
                MapSet.member?(@selected_members, member.id) &&
                  "ring-2 ring-blue-500 dark:ring-blue-400",
                !MapSet.member?(@selected_members, member.id) &&
                  "ring-gray-200/50 dark:ring-gray-700/50 hover:shadow-lg hover:ring-gray-300 dark:hover:ring-gray-600"
              ]}>
                <!-- Selection Checkbox -->
                <div class="absolute top-4 left-4 z-10">
                  <label class="flex items-center">
                    <input
                      type="checkbox"
                      class="form-checkbox h-5 w-5 text-blue-600 rounded border-gray-300 focus:ring-blue-500"
                      checked={MapSet.member?(@selected_members, member.id)}
                      phx-click="toggle-member"
                      phx-value-id={member.id}
                    />
                  </label>
                </div>

                <!-- Status Indicator -->
                <div class="absolute top-4 right-4">
                  <%= if member.status == :online do %>
                    <div class="flex items-center gap-1.5">
                      <div class="w-2 h-2 rounded-full bg-green-500"></div>
                      <span class="text-xs text-gray-500 dark:text-gray-400">Online</span>
                    </div>
                  <% end %>
                </div>

                <div class="p-6">
                  <div class="flex flex-col items-center text-center mb-4">
                    <div class="relative mb-3">
                      <img
                        src={member.avatar_url}
                        alt={member.name}
                        class="w-20 h-20 rounded-full object-cover ring-4 ring-white dark:ring-gray-800"
                      />
                      <%= if member.role.admin do %>
                        <div class="absolute -bottom-1 -right-1 bg-blue-500 text-white rounded-full p-1">
                          <.icon name="hero-shield-check" class="w-4 h-4" />
                        </div>
                      <% end %>
                    </div>
                    <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
                      <%= member.name %>
                    </h3>
                    <p class="text-sm text-gray-500 dark:text-gray-400">
                      <%= member.email %>
                    </p>
                  </div>

                  <div class="space-y-3 mb-6">
                    <!-- Role Badge -->
                    <div class="flex items-center justify-center gap-2">
                      <span class={[
                        "px-3 py-1 text-xs font-medium rounded-full",
                        role_colors(member.role.name)
                      ]}>
                        <%= member.role.name %>
                      </span>
                    </div>

                    <!-- Department -->
                    <div class="flex items-center justify-center gap-2 text-sm text-gray-500 dark:text-gray-400">
                      <.icon name="hero-building-office" class="w-4 h-4" />
                      <span><%= member.department %></span>
                    </div>

                    <!-- Product Access -->
                    <div class="flex flex-col items-center">
                      <span class="text-xs text-gray-500 dark:text-gray-400 mb-2">
                        Product Access
                      </span>
                      <div class="flex -space-x-2">
                        <%= for product <- Enum.take(member.products, 3) do %>
                          <div
                            class="w-8 h-8 rounded-full ring-2 ring-white dark:ring-gray-800 flex items-center justify-center bg-gray-100 dark:bg-gray-700"
                            title={product.name}
                          >
                            <.icon name={product.icon} class="w-4 h-4 text-gray-600 dark:text-gray-300" />
                          </div>
                        <% end %>
                        <%= if length(member.products) > 3 do %>
                          <div class="w-8 h-8 rounded-full ring-2 ring-white dark:ring-gray-800 flex items-center justify-center bg-gray-100 dark:bg-gray-700">
                            <span class="text-xs text-gray-600 dark:text-gray-300">
                              +<%= length(member.products) - 3 %>
                            </span>
                          </div>
                        <% end %>
                      </div>
                    </div>

                    <!-- Last Activity -->
                    <div class="text-xs text-center text-gray-500 dark:text-gray-400">
                      Last active <%= member.last_active %>
                    </div>
                  </div>

                  <div class="flex gap-2">
                    <button class="flex-1 px-3 py-2 text-sm font-medium rounded-xl text-gray-700 bg-gray-100 hover:bg-gray-200 dark:text-gray-300 dark:bg-gray-700 dark:hover:bg-gray-600 transition-colors duration-200">
                      Edit Access
                    </button>
                    <button class="flex-1 px-3 py-2 text-sm font-medium rounded-xl text-blue-600 bg-blue-50 hover:bg-blue-100 dark:text-blue-400 dark:bg-blue-900/30 dark:hover:bg-blue-900/50 transition-colors duration-200">
                      View Details
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <!-- List View -->
          <div class="bg-white dark:bg-gray-800 rounded-2xl shadow-sm ring-1 ring-gray-200/50 dark:ring-gray-700/50">
            <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <thead class="bg-gray-50 dark:bg-gray-900/50">
                <tr>
                  <th scope="col" class="w-8 py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 dark:text-white">
                    <input
                      type="checkbox"
                      class="form-checkbox h-4 w-4 text-blue-600 rounded border-gray-300 focus:ring-blue-500"
                    />
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                    Member
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                    Role
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                    Department
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                    Products
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900 dark:text-white">
                    Status
                  </th>
                  <th scope="col" class="relative py-3.5 pl-3 pr-4">
                    <span class="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                <%= for member <- @members do %>
                  <tr class="hover:bg-gray-50 dark:hover:bg-gray-700/50">
                    <td class="whitespace-nowrap py-4 pl-4 pr-3">
                      <input
                        type="checkbox"
                        class="form-checkbox h-4 w-4 text-blue-600 rounded border-gray-300 focus:ring-blue-500"
                        checked={MapSet.member?(@selected_members, member.id)}
                        phx-click="toggle-member"
                        phx-value-id={member.id}
                      />
                    </td>
                    <td class="whitespace-nowrap px-3 py-4">
                      <div class="flex items-center gap-3">
                        <img
                          src={member.avatar_url}
                          alt={member.name}
                          class="w-10 h-10 rounded-full object-cover"
                        />
                        <div>
                          <div class="font-medium text-gray-900 dark:text-white">
                            <%= member.name %>
                          </div>
                          <div class="text-sm text-gray-500 dark:text-gray-400">
                            <%= member.email %>
                          </div>
                        </div>
                      </div>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4">
                      <span class={[
                        "px-2.5 py-0.5 text-xs font-medium rounded-full",
                        role_colors(member.role.name)
                      ]}>
                        <%= member.role.name %>
                      </span>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500 dark:text-gray-400">
                      <%= member.department %>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4">
                      <div class="flex -space-x-2">
                        <%= for product <- Enum.take(member.products, 3) do %>
                          <div
                            class="w-8 h-8 rounded-full ring-2 ring-white dark:ring-gray-800 flex items-center justify-center bg-gray-100 dark:bg-gray-700"
                            title={product.name}
                          >
                            <.icon name={product.icon} class="w-4 h-4 text-gray-600 dark:text-gray-300" />
                          </div>
                        <% end %>
                        <%= if length(member.products) > 3 do %>
                          <div class="w-8 h-8 rounded-full ring-2 ring-white dark:ring-gray-800 flex items-center justify-center bg-gray-100 dark:bg-gray-700">
                            <span class="text-xs text-gray-600 dark:text-gray-300">
                              +<%= length(member.products) - 3 %>
                            </span>
                          </div>
                        <% end %>
                      </div>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4">
                      <div class="flex items-center gap-1.5">
                        <div class={[
                          "w-2 h-2 rounded-full",
                          member.status == :online && "bg-green-500",
                          member.status == :offline && "bg-gray-400"
                        ]}></div>
                        <span class="text-sm text-gray-500 dark:text-gray-400">
                          <%= if member.status == :online, do: "Online", else: "Offline" %>
                        </span>
                      </div>
                    </td>
                    <td class="whitespace-nowrap py-4 pl-3 pr-4 text-right">
                      <button class="text-gray-400 hover:text-gray-500">
                        <.icon name="hero-ellipsis-vertical" class="w-5 h-5" />
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>

        <!-- Invite Modal -->
        <%= if @show_invite_modal do %>
          <div class="fixed z-50 inset-0 overflow-y-auto">
            <div class="flex items-center justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
              <div class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"></div>

              <div class="inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
                <div class="px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                  <h3 class="text-lg font-medium leading-6 text-gray-900 dark:text-white mb-4">
                    Invite Team Members
                  </h3>

                  <div class="space-y-4">
                    <div>
                      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                        Email Addresses
                      </label>
                      <textarea
                        class="w-full h-24 px-3 py-2 text-sm rounded-lg border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600"
                        placeholder="Enter email addresses (one per line)"
                      ></textarea>
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                        Role
                      </label>
                      <select class="w-full px-3 py-2 text-sm rounded-lg border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600">
                        <%= for role <- @roles do %>
                          <option value={role.id}><%= role.name %></option>
                        <% end %>
                      </select>
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                        Department
                      </label>
                      <select class="w-full px-3 py-2 text-sm rounded-lg border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600">
                        <%= for dept <- @departments do %>
                          <option value={dept.id}><%= dept.name %></option>
                        <% end %>
                      </select>
                    </div>

                    <div>
                      <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
                        Product Access
                      </label>
                      <div class="space-y-2">
                        <%= for product <- get_dummy_products() do %>
                          <label class="flex items-center gap-2">
                            <input
                              type="checkbox"
                              class="form-checkbox h-4 w-4 text-blue-600 rounded border-gray-300 focus:ring-blue-500"
                            />
                            <span class="text-sm text-gray-700 dark:text-gray-300">
                              <%= product.name %>
                            </span>
                          </label>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse bg-gray-50 dark:bg-gray-700">
                  <button
                    type="button"
                    class="w-full inline-flex justify-center rounded-lg border border-transparent shadow-sm px-4 py-2 bg-blue-600 text-base font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:ml-3 sm:w-auto sm:text-sm"
                    phx-click="send-invites"
                  >
                    Send Invites
                  </button>
                  <button
                    type="button"
                    class="mt-3 w-full inline-flex justify-center rounded-lg border border-gray-300 shadow-sm px-4 py-2 bg-white text-base font-medium text-gray-700 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm dark:bg-gray-800 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-700"
                    phx-click="toggle-invite-modal"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper functions

  defp get_dummy_stats do
    [
      %{
        label: "Total Members",
        value: "148",
        icon: "hero-users",
        type: :primary,
        trend: 12
      },
      %{
        label: "Active Now",
        value: "48",
        icon: "hero-circle-stack",
        type: :success,
        trend: 8
      },
      %{
        label: "Pending Invites",
        value: "6",
        icon: "hero-envelope",
        type: :warning,
        trend: -2
      },
      %{
        label: "Average Products",
        value: "4.2",
        icon: "hero-chart-bar",
        type: :info,
        trend: 15
      }
    ]
  end

  defp get_dummy_members do
    [
      %{
        id: 1,
        name: "Sarah Chen",
        email: "sarah@example.com",
        avatar_url: "https://i.pravatar.cc/150?img=1",
        role: %{name: "Admin", admin: true},
        department: "Engineering",
        status: :online,
        products: [
          %{name: "GitHub", icon: "hero-code-bracket"},
          %{name: "Slack", icon: "hero-chat-bubble-left-right"},
          %{name: "Figma", icon: "hero-pencil"},
          %{name: "Notion", icon: "hero-document"}
        ],
        last_active: "2 minutes ago"
      },
      %{
        id: 2,
        name: "Michael Torres",
        email: "michael@example.com",
        avatar_url: "https://i.pravatar.cc/150?img=2",
        role: %{name: "Member", admin: false},
        department: "Design",
        status: :online,
        products: [
          %{name: "Figma", icon: "hero-pencil"},
          %{name: "Slack", icon: "hero-chat-bubble-left-right"}
        ],
        last_active: "5 minutes ago"
      }
      # Add more dummy members...
    ]
  end

  defp get_dummy_departments do
    [
      %{id: "all", name: "All Departments"},
      %{id: "engineering", name: "Engineering"},
      %{id: "design", name: "Design"},
      %{id: "marketing", name: "Marketing"},
      %{id: "sales", name: "Sales"}
    ]
  end

  defp get_dummy_roles do
    [
      %{id: "admin", name: "Admin"},
      %{id: "member", name: "Member"},
      %{id: "guest", name: "Guest"}
    ]
  end

  defp get_dummy_products do
    [
      %{id: 1, name: "GitHub Enterprise"},
      %{id: 2, name: "Slack"},
      %{id: 3, name: "Figma"},
      %{id: 4, name: "Notion"}
    ]
  end

  defp stat_background_color(type) do
    case type do
      :primary -> "bg-blue-50 dark:bg-blue-900/30"
      :success -> "bg-green-50 dark:bg-green-900/30"
      :warning -> "bg-amber-50 dark:bg-amber-900/30"
      :info -> "bg-purple-50 dark:bg-purple-900/30"
      _ -> "bg-gray-50 dark:bg-gray-900/30"
    end
  end

  defp stat_icon_color(type) do
    case type do
      :primary -> "text-blue-600 dark:text-blue-400"
      :success -> "text-green-600 dark:text-green-400"
      :warning -> "text-amber-600 dark:text-amber-400"
      :info -> "text-purple-600 dark:text-purple-400"
      _ -> "text-gray-600 dark:text-gray-400"
    end
  end

  defp role_colors(role) do
    case role do
      "Admin" -> "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400"
      "Member" -> "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400"
      "Guest" -> "bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400"
      _ -> "bg-gray-100 text-gray-800 dark:bg-gray-900/30 dark:text-gray-400"
    end
  end

  # Event handlers
  @impl true
  def handle_event("toggle-invite-modal", _, socket) do
    {:noreply, assign(socket, show_invite_modal: !socket.assigns.show_invite_modal)}
  end

  def handle_event("set-view", %{"view" => view}, socket) do
    {:noreply, assign(socket, view: view)}
  end

  def handle_event("filter-department", %{"department" => department}, socket) do
    {:noreply, assign(socket, selected_department: department)}
  end

  def handle_event("search", %{"value" => search}, socket) do
    {:noreply, assign(socket, search: search)}
  end

  def handle_event("toggle-member", %{"id" => id}, socket) do
    member_id = String.to_integer(id)
    selected_members =
      if MapSet.member?(socket.assigns.selected_members, member_id) do
        MapSet.delete(socket.assigns.selected_members, member_id)
      else
        MapSet.put(socket.assigns.selected_members, member_id)
      end

    {:noreply, assign(socket, selected_members: selected_members)}
  end

  def handle_event("clear-selection", _, socket) do
    {:noreply, assign(socket, selected_members: MapSet.new())}
  end

  def handle_event("send-invites", _, socket) do
    # Handle sending invites
    {:noreply, socket}
  end
end
