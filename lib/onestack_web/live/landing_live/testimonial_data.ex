defmodule OnestackWeb.Live.LandingLive.TestimonialData do
  @moduledoc """
  Module containing testimonial data for the landing page.
  """

  @doc """
  Returns a list of testimonial cards with user information and quotes.
  """
  def testimonial_cards do
    [
      %{
        name: "Josephine Tay",
        avatar_url:
          "https://media.licdn.com/dms/image/v2/D4D03AQGxK2fubZsmNg/profile-displayphoto-shrink_800_800/profile-displayphoto-shrink_800_800/0/1731558877431?e=1746057600&v=beta&t=8sQTK8KNUV_fC88O8--1gUBCk-2TSEMd39kCDmSBNm0",
        testimonial:
          "Ben and George are the kind of founders you bet on. Customer-obsessed to the core, resilient and always hungry to learn and adapt. They've poured so much love and attention to detail into Onestack, crafting a flawless UI and a seamless customer experience. Their product capabilities are truly world-class.
",
        company_logo_url:
          "https://media.licdn.com/dms/image/v2/D560BAQENVztG9ZiJdA/company-logo_200_200/B56ZUB8crlGQAI-/0/1739494378670/blackbirdvc_logo?e=1749081600&v=beta&t=tZC2Km7xtAx6hZnh5rA4TDYjiiamcdm2WnijQzBcsOo"
      },
      %{
        name: "Thomas Pasturel",
        avatar_url:
          "https://media.licdn.com/dms/image/v2/D4E03AQE-lT5C6iHdOg/profile-displayphoto-shrink_400_400/B4EZSCA2hxHgAg-/0/1737348049809?e=1746662400&v=beta&t=N5s78Rilx_6J88Q8NvH4YVcPWP_AVt8-1aZv7UBOH78",
        testimonial:
          "Onestack is a very welcome addition to my tech stack. As a business growth and SEO consultant, I use a lot of SaaS tools and can vouch for what George and Ben have built. It’s a robust offering based on a smart business model. More importantly: they really listen to user feedback and build the product around it.",
        company_logo_url:
          "https://media.licdn.com/dms/image/v2/C560BAQG0OagODL66gA/company-logo_200_200/company-logo_200_200/0/1630661445920?e=1749081600&v=beta&t=t2V6cn9v4AMKVPoiN2lG9eX4vxt5rC02XRMAqBt79jY"
      },
      %{
        name: "Riana Prigg",
        avatar_url:
          "https://media.licdn.com/dms/image/v2/D5603AQFellbR-D20xQ/profile-displayphoto-shrink_400_400/profile-displayphoto-shrink_400_400/0/1729547907346?e=1746662400&v=beta&t=dlR7Ia-Zjw7ohFsqxAuQPUXnRXnJKFrizizVNX3K6sM",
        testimonial:
          "Onestack has made managing my software stack easy and affordable. As a small business owner, my biggest overheads were in the many subscriptions and software platforms I needed to run my business but now Onestack looks after 85% of my platforms and it’s saving me a fortune in money, time and mental energy!",
        company_logo_url:
          "https://media.licdn.com/dms/image/v2/D560BAQH6Jff2CWZJrA/company-logo_200_200/B56ZUl3Z7AGUAM-/0/1740097036336/rivaandco_logo?e=1749081600&v=beta&t=QJv6xzVy0EFJ1wwKRxV0P9nQIe8no2HRqvT9qNxMLVA"
      }
    ]
  end
end
