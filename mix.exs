if System.otp_release() < "25" do
  Mix.raise("Livebook requires Erlang/OTP 25+")
end

defmodule Livebook.MixProject do
  use Mix.Project

  @elixir_requirement "~> 1.18"
  @version "0.15.0-dev"
  @description "Automate code & data workflows with interactive notebooks"

  def project do
    [
      app: :livebook,
      version: @version,
      elixir: @elixir_requirement,
      name: "Livebook",
      description: @description,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_elixirc_options: [docs: true],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: with_lock(target_deps(Mix.target()) ++ deps()),
      escript: escript(),
      package: package(),
      default_release: :livebook,
      releases: releases(),

      # Docs
      homepage_url: "https://livebook.dev",
      docs: &docs/0
    ]
  end

  def application do
    [
      mod: {Livebook.Application, []},
      extra_applications: [
        :logger,
        :runtime_tools,
        :os_mon,
        :inets,
        :ssl,
        :xmerl,
        :crypto,
        :public_key
      ],
      env: Application.get_all_env(:livebook)
    ]
  end

  defp elixirc_paths(:test), do: elixirc_paths(:dev) ++ ["test/support"]
  defp elixirc_paths(_), do: ["lib", "proto/lib"]

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/livebook-dev/livebook"
      },
      files:
        ~w(lib static priv/.gitkeep config mix.exs mix.lock README.md LICENSE CHANGELOG.md iframe/priv/static/iframe proto/lib)
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd --cd assets npm install"],
      "assets.deploy": ["cmd npm run deploy --prefix assets"],
      "format.all": ["format", "cmd --cd assets npm run --silent format"],
      "protobuf.generate": ["cmd --cd proto mix protobuf.generate"],
      "phx.server": ["livebook.gen_priv", "phx.server"],
      "escript.build": ["livebook.gen_priv", "escript.build"],
      release: ["livebook.gen_priv", "release"]
    ]
  end

  defp escript do
    [
      main_module: LivebookCLI,
      app: nil,
      emu_args: "-epmd_module Elixir.Livebook.EPMD",
      include_priv_for: [:livebook]
    ]
  end

  ## Dependencies

  # Although we use requirements here, the with_lock() function
  # below ensures we only use the locked versions. This is important
  # for two reasons:
  #
  #   1. because we bundle assets from phoenix, phoenix_live_view,
  #      and phoenix_html, we want to make sure we have those exact
  #      versions
  #
  #   2. we don't want users to potentially get a new dependency
  #      when installing from git or as an escript
  #
  # Therefore, to update any dependency, you must call before:
  #
  #     mix deps.unlock foo bar baz
  #
  defp deps do
    [
      {:phoenix, "~> 1.7.8"},
      {:phoenix_live_view, "~> 1.0.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_dashboard, "~> 0.8.4"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.16"},
      {:plug_crypto, "~> 2.0"},
      {:earmark_parser, "~> 1.4"},
      {:ecto, "~> 3.10"},
      {:phoenix_ecto, "~> 4.4"},
      {:aws_credentials, "~> 0.3.0", runtime: false},
      {:mint_web_socket, "~> 1.0.0"},
      {:protobuf, "~> 0.13.0"},
      {:dns_cluster, "~> 0.1.2"},
      {:kubereq, "~> 0.3.0"},
      {:yaml_elixir, "~> 2.11"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:floki, ">= 0.27.0", only: :test},
      {:bypass, "~> 2.1", only: :test},
      # ZTA deps
      {:jose, "~> 1.11.5"},
      {:req, "~> 0.5.8"},
      # Docs
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  defp target_deps(:app), do: [{:elixirkit, path: "elixirkit"}]
  defp target_deps(_), do: []

  @lock (with {:ok, contents} <- File.read("mix.lock"),
              {:ok, quoted} <-
                Code.string_to_quoted(contents,
                  warn_on_unnecessary_quotes: false,
                  emit_warnings: false
                ),
              {%{} = lock, _binding} <- Code.eval_quoted(quoted, []) do
           for {dep, hex} when elem(hex, 0) == :hex <- lock,
               do: {dep, elem(hex, 2)},
               into: %{}
         else
           _ -> %{}
         end)

  defp with_lock(deps) do
    for dep <- deps do
      name = elem(dep, 0)
      put_elem(dep, 1, @lock[name] || elem(dep, 1))
    end
  end

  ## Releases

  # aws_credentials has runtime: false, so explicitly add is as :load
  @release_apps [livebook: :permanent, aws_credentials: :load]

  defp releases do
    [
      livebook: [
        applications: @release_apps,
        include_executables_for: [:unix, :windows],
        include_erts: false,
        rel_templates_path: "rel/server",
        steps: [:assemble, &remove_cookie/1, &write_runtime_modules/1]
      ],
      app: [
        applications: @release_apps,
        include_erts: false,
        rel_templates_path: "rel/app",
        steps: [
          :assemble,
          &remove_cookie/1,
          &standalone_erlang_elixir/1
        ]
      ]
    ]
  end

  defp remove_cookie(release) do
    # We remove the COOKIE file when assembling the release, because we
    # don't want to share the same cookie across users.
    File.rm!(Path.join(release.path, "releases/COOKIE"))
    release
  end

  defp write_runtime_modules(release) do
    # We copy the subset of Livebook modules that are injected into
    # the runtime node. See overlays/bin/server for more details

    app = release.applications[:livebook]

    source = Path.join([release.path, "lib", "livebook-#{app[:vsn]}", "ebin"])
    destination = Path.join([release.path, "lib", "livebook_runtime_ebin"])

    File.mkdir_p!(destination)

    for module <- Livebook.Runtime.ErlDist.required_modules() do
      from = Path.join(source, "#{module}.beam")
      to = Path.join(destination, "#{module}.beam")
      File.cp!(from, to)
    end

    release
  end

  @compile {:no_warn_undefined, Standalone}

  defp standalone_erlang_elixir(release) do
    {_, bindings} = Code.eval_file("versions")
    elixir_version = bindings[:elixir]
    rebar3_version = bindings[:rebar3]

    Code.require_file("rel/app/standalone.exs")

    release
    |> Standalone.copy_otp()
    |> Standalone.copy_elixir(elixir_version)
    |> Standalone.copy_hex()
    |> Standalone.copy_rebar3(rebar3_version)
  end

  defp docs() do
    [
      logo: "static/images/logo.png",
      main: "readme",
      api_reference: false,
      extra_section: "Guides",
      extras: extras(),
      filter_modules: fn mod, _ -> mod in [Livebook] end,
      assets: %{Path.expand("./docs/images") => "images"},
      groups_for_extras: [
        "Livebook Teams": Path.wildcard("docs/teams/*"),
        Deployment: Path.wildcard("docs/deployment/*"),
        "Airgapped Authentication": Path.wildcard("docs/authentication/*")
      ]
    ]
  end

  defp extras() do
    [
      {"README.md", title: "Welcome to Livebook"},
      "docs/use_cases.md",
      "docs/authentication.md",
      "docs/stamping.md",
      "docs/deployment/docker.md",
      "docs/deployment/clustering.md",
      "docs/deployment/fips.md",
      "docs/deployment/nginx_https.md",
      "docs/teams/intro_to_teams.md",
      "docs/teams/shared_secrets.md",
      "docs/teams/shared_file_storages.md",
      {"docs/teams/oidc_sso.md", title: "OIDC SSO"},
      "docs/authentication/basic_auth.md",
      "docs/authentication/cloudflare.md",
      "docs/authentication/google_iap.md",
      "docs/authentication/tailscale.md",
      "docs/authentication/custom_auth.md"
    ]
  end
end
