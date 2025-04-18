defmodule BroadwayKinesis.MixProject do
  use Mix.Project

  def project do
    [
      app: :broadway_kinesis,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bypass, "~> 2.1", only: :test},
      {:event_stream, "~> 0.1.0"},
      {:ex_aws, "~> 2.1"},
      {:ex_aws_kinesis, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:jason, "~> 1.4"},
      {:mint, "~> 1.0"},
      {:sweet_xml, "~> 0.6"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
