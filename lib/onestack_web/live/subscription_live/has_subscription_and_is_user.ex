defmodule OnestackWeb.SubscribeLive.HasSubscriptionAndIsUser do
  use OnestackWeb, :live_component

  def render(assigns) do
    ~H"""
    <section class="py-8 lg:py-20 min-h-screen" id="subscribe">
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-4xl font-semibold" id="products">My Stack</h2>
          <p class="text-sm text-gray-500 mt-2">
            View and launch your products
          </p>
        </div>

        <div class="flex flex-col md:flex-row gap-8">
          <!-- My Stack -->
          <div class="w-full max-w-xl mx-auto">
            <div class="card bg-base-200 shadow-xl">
              <div class="card-body">
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
                        <div class="flex items-center">
                          <a
                            href={
                              if String.downcase(product.name) == "matrix",
                                do: "https://app.element.io/",
                                else: "https://#{String.downcase(product.name)}.onestack.cloud"
                            }
                            target="_blank"
                            rel="noopener noreferrer"
                            class="btn btn-primary btn-xs"
                          >
                            Launch
                          </a>
                        </div>
                      </li>
                    <% end %>
                  <% end %>
                </ul>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
