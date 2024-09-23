# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :sitemap,
  compress: false,
  host: "https://onestack.cloud",
  files_path: Path.join(["priv", "static", "sitemap"])

config :onestack,
  ecto_repos: [Onestack.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :onestack, OnestackWeb.Endpoint,
  url: [host: System.get_env("PHX_HOST")],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: OnestackWeb.ErrorHTML, json: OnestackWeb.ErrorJSON],
    layout: false
  ],
  check_origin: ["https://onestack.cloud", "https://dev.onestack.cloud"],
  pubsub_server: Onestack.PubSub,
  live_view: [signing_salt: "AYfWDwt/"]

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
  region: "ap-southeast-2",
  access_key: "REDACTED_AWS_ACCESS_KEY",
  secret: "REDACTED_AWS_SECRET_KEY"

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
  version: "3.4.0",
  onestack: [
    args: ~w(
      --config=tailwind.config.js
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

config :onestack,
  products: [
    %{
      name: "formbricks",
      db_config: [
        hostname: "5.78.111.23",
        port: 5433,
        username: "onestack-cal",
        password: "REDACTED_POSTGRES_PASSWORD",
        database: "formbricks"
      ]
    },
    %{
      name: "cal",
      db_config: [
        hostname: "5.78.111.23",
        port: 5433,
        username: "onestack-cal",
        password: "REDACTED_POSTGRES_PASSWORD",
        database: "onestack-cal"
      ]
    },
    %{
      name: "castopod",
      db_config: [
        hostname: "5.78.111.23",
        port: 5332,
        username: "root",
        password: "REDACTED_MARIADB_PASSWORD",
        database: "castopod"
      ]
    },
    %{
      name: "n8n",
      db_config: [
        hostname: "5.78.111.23",
        port: 5433,
        username: "onestack-cal",
        password: "REDACTED_POSTGRES_PASSWORD",
        database: "n8n"
      ]
    },
    %{
      name: "documenso",
      db_config: [
        hostname: "5.78.111.23",
        port: 5433,
        username: "onestack-cal",
        password: "REDACTED_POSTGRES_PASSWORD",
        database: "documenso"
      ]
    },
    %{
      name: "nocodb",
      db_config: [
        hostname: "5.78.111.23",
        port: 5433,
        username: "onestack-cal",
        password: "REDACTED_POSTGRES_PASSWORD",
        database: "nocodb"
      ]
    },
    %{
      name: "chatwoot",
      db_config: [
        hostname: "5.78.111.23",
        port: 5433,
        username: "onestack-cal",
        password: "REDACTED_POSTGRES_PASSWORD",
        database: "chatwoot"
      ]
    },
    %{
      name: "penpot",
      db_config: [
        hostname: "5.78.111.23",
        port: 5433,
        username: "onestack-cal",
        password: "REDACTED_POSTGRES_PASSWORD",
        database: "penpot"
      ]
    }
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
