# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sitemap,
  compress: false,
  host: System.get_env("PHX_HOST", "http://localhost:4000"),
  files_path: Path.join(["priv", "static", "sitemap"])

config :onestack,
  ecto_repos: [Onestack.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :onestack, OnestackWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST", "http://localhost:4000")],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: OnestackWeb.ErrorHTML, json: OnestackWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Onestack.PubSub,
  live_view: [signing_salt: System.get_env("CONFIG_SIGNING_SALT")]

# static_url: [path: "/"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
# config :onestack, Onestack.Mailer, adapter: Swoosh.Adapters.Local

# api_client: Swoosh.ApiClient.Hackney

config :onestack, Onestack.Mailer,
  adapter: Swoosh.Adapters.AmazonSES,
  region: System.get_env("AWS_SES_REGION"),
  access_key: System.get_env("AWS_SES_ACCESS_KEY"),
  secret: System.get_env("AWS_SES_SECRET")

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  onestack: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.0",
  onestack: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :money,
  default_currency: :AUD,
  separator: ".",
  delimiter: ".",
  symbol: true,
  symbol_on_right: false,
  symbol_space: false,
  fractional_unit: true,
  strip_insignificant_zeros: false,
  code: false,
  minus_sign_first: true,
  strip_insignificant_fractional_unit: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
