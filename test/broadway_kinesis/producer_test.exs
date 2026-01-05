defmodule BroadwayKinesis.ProducerTest do
  use ExUnit.Case
  require BroadwayKinesis.Producer

  defmodule FailingSubscribeToShard do
    def subscribe(consumer_arn, shard_id, starting_position, options \\ []) do
      raise "MANUAL EXCEPTION: Connection Refused"
    end
  end

  defmodule FakeProducer do
    use BroadwayKinesis.Producer,
      consumer_arn: "fake_consumer_arn",
      stream_name: "fake_stream_name",
      subscribe_to_shard_module: FailingSubscribeToShard
  end

  describe "initial Kinesis connection" do
    test "failure results in retry" do
      assert capture_log(fn -> FakeProducer.init() end) =~
               "Initial Kinesis connection unsuccessful:"
    end
  end
end
