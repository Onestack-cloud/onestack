defmodule Onestack do
  @moduledoc """
  Onestack keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc "Returns true when Stripe integration is configured and enabled."
  def stripe_enabled?, do: Application.get_env(:onestack, :stripe_enabled, false)
end
