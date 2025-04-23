# BroadwayKinesis

A [Broadway](https://github.com/dashbitco/broadway) connector for [Amazon Kinesis](https://aws.amazon.com/kinesis/).

Utilizes the [SubscribeToShard](https://docs.aws.amazon.com/kinesis/latest/APIReference/API_SubscribeToShard.html) action to stream data.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `broadway_kinesis` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:broadway_kinesis, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/broadway_kinesis>.

