defmodule OnestackWeb.SubscribeLive.NoSubscription do
  use OnestackWeb, :live_component

  def render(assigns) do
    ~H"""
    <section class="py-8 lg:py-20 min-h-screen" id="subscribe">
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-4xl font-semibold" id="products">Create Your Stack</h2>
          <p class="text-sm text-gray-500 mt-2">
            Click on a product to add it to your stack
          </p>
        </div>

        <div class="flex flex-col md:flex-row gap-8">
          <!-- Available Products -->
          <div class="w-full md:w-2/3">
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
                        phx-click="select_product"
                        phx-value-product={product.id}
                      >
                        <td class="flex items-center">
                          <img
                            src={"https://onestack-images.pages.dev/#{URI.encode_www_form(product.name)}.png"}
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
          <div class="w-full md:w-1/2">
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
                              src={"https://onestack-images.pages.dev/#{URI.encode_www_form(product.name)}.png"}
                              class="h-6 w-6 mask mask-squircle object-contain mr-2"
                              alt={product.name}
                            />
                            <span><%= product.name %></span>
                          </div>
                          <button
                            class="btn btn-error btn-xs"
                            phx-click="select_product"
                            phx-value-product={product.id}
                          >
                            Remove
                          </button>
                        </li>
                      <% end %>
                    <% end %>
                  </ul>
                <% end %>

                <button
                  class="btn btn-primary w-full mt-6"
                  phx-click="subscribe"
                  phx-disable-with="Creating stack..."
                >
                  Create Stack
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
