import Config

# Default bind and port for production
config :livebook, LivebookWeb.Endpoint,
  http: [
    ip: {127, 0, 0, 1},
    port: 8080,
    http_1_options: [max_header_length: 32768],
    http_2_options: [max_header_value_length: 32768]
  ],
  server: true

config :livebook, :iframe_port, 8081

# Set log level to warning by default to reduce output
config :logger, level: :warning

config :livebook, Livebook.Copilot,
  enabled: true,
  backend: Livebook.Copilot.BumblebeeBackend,
  backend_config: %{
    model: "deepseek-coder-1.3b",
    client: :cuda
  }

# backend_config: %{
#   model: "gpt2",
#   client: :host
# }

config :nx,
  default_backend: EXLA.Backend,
  device: :cuda,
  client: :cuda

# ## SSL Support
#
# To get SSL working, you will need to add the `https` key
# to the previous section and set your `:url` port to 443:
#
#     config :livebook, LivebookWeb.Endpoint,
#       ...
#       url: [host: "example.com", port: 443],
#       https: [
#         port: 443,
#         cipher_suite: :strong,
#         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
#         certfile: System.get_env("SOME_APP_SSL_CERT_PATH"),
#         transport_options: [socket_opts: [:inet6]]
#       ]
#
# The `cipher_suite` is set to `:strong` to support only the
# latest and more secure SSL ciphers. This means old browsers
# and clients may not be supported. You can set it to
# `:compatible` for wider support.
#
# `:keyfile` and `:certfile` expect an absolute path to the key
# and cert in disk or a relative path inside priv, for example
# "priv/ssl/server.key". For all supported SSL configuration
# options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
#
# We also recommend setting `force_ssl` in your endpoint, ensuring
# no data is ever sent via http, always redirecting to https:
#
#     config :livebook, LivebookWeb.Endpoint,
#       force_ssl: [hsts: true]
#
# Check `Plug.SSL` for all available options in `force_ssl`.
