defmodule OnestackWeb.SubscribeLive.HasSubscriptionAndIsAdmin do
  use OnestackWeb, :live_component

  def render(assigns) do
    ~H"""
    <section class="py-8 lg:py-20 min-h-screen" id="subscribe">
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-4xl font-semibold" id="products">Manage My Stack</h2>
          <p class="text-sm text-gray-500 mt-2">
            Welcome to the control center for your entire stack.
          </p>
        </div>

        <div class="flex flex-col-reverse xl:flex-row gap-8">
          <!-- Available Products -->
          <div class="w-full xl:w-2/3">
            <h3 class="text-2xl font-semibold mb-4">Available Products</h3>
            <div class="overflow-x-auto">
              <table class="table">
                <thead>
                  <tr>
                    <th>Product</th>
                    <th>Description</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for product <- @products do %>
                    <%= if !Enum.member?(@selected_products, product.id) do %>
                      <tr
                        class="cursor-pointer hover:bg-base-200 transition-colors duration-200"
                        phx-click="open_modal"
                        phx-value-product={product.id}
                        phx-value-action="add"
                      >
                        <td class="flex items-center">
                          <img
                            src={"https://onestack-images.pages.dev/#{URI.encode_www_form(String.downcase(product.name))}.png"}
                            class="h-8 w-8 object-contain mask mask-squircle mr-2"
                            alt={product.name}
                          />
                          <%= product.name %>
                        </td>
                        <td><%= product.description %></td>
                        <td class="text-center">
                          <span class="btn btn-primary btn-xs w-20" aria-label={product.name}>
                            Add
                          </span>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
          <!-- My Stack -->
          <div class="w-full xl:w-1/2">
            <div class="card bg-base-200 shadow-xl">
              <div class="card-body">
                <h3 class="card-title">My Stack</h3>
                <%= if Enum.empty?(@selected_products) do %>
                  <p class="text-gray-500">Your stack is empty. Add products to get started!</p>
                <% else %>
                  <ul class="space-y-2">
                    <%= for product <- @products do %>
                      <%= if Enum.member?(@selected_products, product.id) do %>
                        <li class="flex items-center justify-between bg-base-200 rounded-md p-2">
                          <div class="flex items-center">
                            <img
                              src={"https://onestack-images.pages.dev/#{URI.encode_www_form(String.downcase(product.name))}.png"}
                              class="h-6 w-6 mask mask-squircle object-contain mr-2"
                              alt={product.name}
                            />
                            <span><%= product.name %></span>
                          </div>
                          <div class="flex items-center">
                            <a
                              href={
                                if String.downcase(product.name) == "matrix",
                                  do: "https://app.element.io/",
                                  else: "https://#{String.downcase(product.name)}.onestack.cloud"
                              }
                              target="_blank"
                              rel="noopener noreferrer"
                              class="btn btn-primary btn-xs mr-8"
                            >
                              Launch
                            </a>
                            <button
                              class="text-gray-500 hover:text-error transition-colors duration-200 text-2xl"
                              phx-click="open_modal"
                              phx-value-product={product.id}
                              phx-value-action="remove"
                            >
                              ×
                            </button>
                          </div>
                        </li>
                      <% end %>
                    <% end %>
                  </ul>
                <% end %>

                <div class="mt-8">
                  <h2 class="card-title mb-4">My team</h2>
                  <div class="my-6 mb-12">
                    <form phx-submit="add_member" class="flex">
                      <input
                        type="email"
                        name="email"
                        placeholder="Enter email address"
                        class="input input-bordered w-full mr-2"
                        required
                      />
                      <button type="submit" class="btn btn-primary">Add</button>
                    </form>
                  </div>
                  <div class="my-6">
                    <%= for email <- @team_members do %>
                      <div class="flex items-center justify-between bg-secondary/10 p-2 rounded-lg mb-2">
                        <span><%= email %></span>
                        <%= if email == @current_user.email do %>
                          <div>
                            <div class="badge badge-warning">Admin</div>
                            <button disabled="true" class="btn btn-sm btn-error">
                              Remove
                            </button>
                          </div>
                        <% else %>
                          <button
                            phx-click="remove_member"
                            phx-value-email={email}
                            class="btn btn-sm btn-error"
                          >
                            Remove
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  <div class="flex items-center justify-between">
                    <progress
                      id="slider"
                      value={@num_users}
                      max={ceil(@num_users / 10) * 10}
                      class="progress w-full"
                      name="num_users"
                    >
                    </progress>
                    <h2 class="ml-4"><%= @num_users %></h2>
                  </div>
                  <div class="stats stats-vertical md:stats-horizontal shadow w-full mt-8">
                    <div class="stat">
                      <div class="stat-title">
                        Next billing date: <%= DateTime.from_unix!(@upcoming_invoice.period_end)
                        |> Calendar.strftime("%B %d") %>
                      </div>
                      <div class="stat-value text-primary">
                        <%= Money.new(
                          @upcoming_invoice.amount_due,
                          String.to_atom(String.upcase(@upcoming_invoice.currency))
                        )
                        |> Money.to_string() %>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <dialog id="subscription_modal" class="modal" open={@show_modal}>
            <%= if @show_modal and @modal_product do %>
              <div class="modal-box relative z-50">
                <h3 class="font-bold text-lg">
                  <%= if @modal_action == "add", do: "Add", else: "Remove" %> <%= @modal_product.name %>
                </h3>
                <p class="py-4">
                  Are you sure you want to <%= @modal_action %> <%= @modal_product.name %>
                  <%= if @modal_action == "add", do: "to", else: "from" %> your subscription?
                </p>
                <div class="modal-action">
                  <button
                    class="btn btn-primary"
                    phx-click="update_subscription"
                    phx-value-action={@modal_action}
                    phx-value-product={@modal_product.id}
                    disabled={@updating}
                  >
                    <%= if @updating do %>
                      <span class="loading loading-spinner"></span>
                      <%= if @modal_action == "add", do: "Adding...", else: "Removing..." %>
                    <% else %>
                      Confirm
                    <% end %>
                  </button>
                  <button class="btn" phx-click="close_modal" disabled={@updating}>Cancel</button>
                </div>
              </div>
            <% end %>
          </dialog>
        </div>
      </div>
      <div class={
        @show_modal &&
          "fixed inset-0 bg-black bg-opacity-50 backdrop-blur"
      }>
      </div>
    </section>
    """
  end
end
