defmodule Onestack.InvitationEmail do
  use Phoenix.Swoosh,
    template_root: "lib/onestack",
    template_path: "email_templates"

  import Swoosh.Email
  alias Onestack.Mailer

  def get_customer_first_name(email) do
    with customers <- Onestack.StripeCache.list_customers(),
         matching_customers <- Enum.filter(customers, fn customer -> customer.email == email end),
         latest_customer <- Enum.max_by(matching_customers, & &1.created, fn -> nil end),
         %Stripe.Customer{name: name} when not is_nil(name) <- latest_customer,
         [first_name | _] <- String.split(name) do
      first_name
    else
      nil ->
        {:error, :customer_not_found}

      %Stripe.Customer{name: nil} ->
        {:error, :name_not_available}

      {:error, error} ->
        {:error, error}

      _ ->
        {:error, :unexpected_error}
    end
  end

  def send_invitation(email_recipient, admin_email, invitation_id) do
    admin_first_name = get_customer_first_name(admin_email)

    email_recipient
    |> invitation_email(invitation_id, admin_email, admin_first_name)
    |> Mailer.deliver()
  end

  defp invitation_email(email_recipient, invitation_id, admin_email, admin_first_name) do
    base_email()
    |> to({email_recipient, email_recipient})
    |> subject("Your Onestack Invite is Here!")
    |> render_body("invitation_email.html", %{
      invitation_id: invitation_id,
      admin_first_name: admin_first_name,
      admin_email: admin_email
    })
  end

  defp base_email do
    new()
    |> from({"Onestack Team", "support@onestack.cloud"})
    |> put_provider_option(:track_opens, true)
  end
end
