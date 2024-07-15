defmodule Onestack.InvitationEmail do
  use Phoenix.Swoosh,
    # view: Onestack.InvitationEmailView,
    template_root: "lib/onestack",
    template_path: "email_templates"

  import Swoosh.Email
  alias Onestack.Mailer

  def send_invitation(email, invitation_link) do
    email
    |> invitation_email(invitation_link)
    |> Mailer.deliver()
  end

  defp invitation_email(email, invitation_link) do
    base_email()
    |> to({email, email})
    |> subject("Welcome to Onestack!")
    |> render_body("invitation_email.html", %{copy_credentials_url: invitation_link})
  end

  defp base_email do
    new()
    |> from({"Onestack Team", "support@onestack.cloud"})
    |> put_provider_option(:track_opens, true)
  end
end
