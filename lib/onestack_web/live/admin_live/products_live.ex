# lib/onestack_web/live/admin/products_live.ex
defmodule OnestackWeb.Admin.ProductsLive do
  use OnestackWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to product updates
    end

    {:ok,
     assign(socket,
       page_title: "Products",
       active_products: get_dummy_active_products(),
       available_products: get_dummy_available_products(),
       categories: get_dummy_categories(),
       selected_category: "all",
       search: "",
       show_product_details: nil,
       total_monthly_savings: "$3,450",
       total_monthly_cost: "$899",
       show_onboarding: false,
       selected_view: "grid",
       show_compare: false,
       current_tab: "active"
     )}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :current_tab, tab)}
  end


  defp get_dummy_active_products do
    [
      %{
        id: 1,
        name: "Slack Enterprise",
        category: "Communication",
        active_users: 85,
        total_seats: 100,
        monthly_savings: "$450",
        status: :warning
      },
      %{
        id: 2,
        name: "Notion Team",
        category: "Productivity",
        active_users: 45,
        total_seats: 100,
        monthly_savings: "$299",
        status: :normal
      },
      %{
        id: 3,
        name: "GitHub Enterprise",
        category: "Development",
        active_users: 32,
        total_seats: 50,
        monthly_savings: "$599",
        status: :normal
      }
    ]
  end

  defp get_dummy_available_products do
    [
      %{
        id: 4,
        name: "Linear",
        category: "Project Management",
        description: "The issue tracking tool you'll enjoy using",
        customers: "2,451",
        rating: 4.9,
        estimated_savings: "$200",
        trending: true
      },
      %{
        id: 5,
        name: "Figma Enterprise",
        category: "Design",
        description: "The collaborative interface design tool",
        customers: "3,877",
        rating: 4.8,
        estimated_savings: "$350",
        trending: false
      },
      %{
        id: 6,
        name: "Retool Enterprise",
        category: "Development",
        description: "Build internal tools remarkably fast",
        customers: "1,988",
        rating: 4.7,
        estimated_savings: "$500",
        trending: true
      }
    ]
  end

  defp get_dummy_categories do
    [
      %{id: "communication", name: "Communication", icon: "hero-chat-bubble-left-right"},
      %{id: "productivity", name: "Productivity", icon: "hero-briefcase"},
      %{id: "development", name: "Development", icon: "hero-code-bracket"},
      %{id: "design", name: "Design", icon: "hero-pencil"},
      %{id: "project-management", name: "Project Management", icon: "hero-rectangle-stack"}
    ]
  end

  defp product_category_color(category) do
    case category do
      "Communication" -> "bg-indigo-100 text-indigo-600 dark:bg-indigo-400/10 dark:text-indigo-400"
      "Productivity" -> "bg-green-100 text-green-600 dark:bg-green-400/10 dark:text-green-400"
      "Development" -> "bg-blue-100 text-blue-600 dark:bg-blue-400/10 dark:text-blue-400"
      "Design" -> "bg-purple-100 text-purple-600 dark:bg-purple-400/10 dark:text-purple-400"
      "Project Management" -> "bg-rose-100 text-rose-600 dark:bg-rose-400/10 dark:text-rose-400"
      _ -> "bg-gray-100 text-gray-600 dark:bg-gray-400/10 dark:text-gray-400"
    end
  end

  defp product_category_icon(category) do
    case category do
      "Communication" -> "hero-chat-bubble-left-right"
      "Productivity" -> "hero-briefcase"
      "Development" -> "hero-code-bracket"
      "Design" -> "hero-pencil"
      "Project Management" -> "hero-rectangle-stack"
      _ -> "hero-cube"
    end
  end

  defp usage_color(percentage) when percentage >= 0.9, do: "bg-red-500"
  defp usage_color(percentage) when percentage >= 0.7, do: "bg-amber-500"
  defp usage_color(_percentage), do: "bg-green-500"
end
