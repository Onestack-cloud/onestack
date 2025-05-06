defmodule Onestack.CustomerCombiner do
  def combine_customers(stripe_customers, subscriptions) do
    subscription_map =
      Enum.reduce(subscriptions, %{}, fn subscription, acc ->
        products = extract_products(subscription)

        Map.put(acc, subscription.customer, %{
          products: products,
          subscription_id: subscription.id
        })
      end)

    stripe_customers
    |> Enum.map(fn %{email: email, id: customer_id} ->
      subscription_info =
        Map.get(subscription_map, customer_id, %{products: [], subscription_id: nil})

      %{
        email: email,
        customer_id: customer_id,
        products: subscription_info.products,
        subscription_id: subscription_info.subscription_id
      }
    end)
    |> Enum.filter(fn customer -> customer.subscription_id != nil end)
  end

  defp extract_products(subscription) do
    subscription.items.data
    |> Enum.map(fn item -> item.price.product end)
    |> Enum.uniq()
  end
end
