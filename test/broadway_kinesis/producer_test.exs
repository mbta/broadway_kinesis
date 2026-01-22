defmodule BroadwayKinesis.ProducerTest do
  use ExUnit.Case

  alias BroadwayKinesis.ProducerRegistry
  import ExUnit.CaptureLog
  import Mock

  defmodule FakeAwsFail do
    def request!(_) do
      raise "FakeAws request failure!"
    end
  end

  defmodule FakeAwsSuccess do
    def request!(_) do
      %{"StreamDescription" => %{"Shards" => [%{"ShardId" => "test-shard-0"}]}}
    end
  end

  defmodule FakeProducer do
    use BroadwayKinesis.Logger

    use BroadwayKinesis.Producer,
      consumer_arn: "fake_consumer_arn",
      stream_name: "fake_stream_name"
  end

  describe "initial Kinesis connection" do
    test "can connect to AWS Shard" do
      {:ok, _pid} =
        start_supervised(
          {ProducerRegistry,
           [name: BroadwayKinesis.ProducerRegistry, registry_name: :test_registry]},
          restart: :temporary
        )

      with_mock BroadwayKinesis.SubscribeToShard,
        subscribe: fn _arn, _shard, _pos, _opts -> {:ok, :conn} end do
        state_overrides = %{
          ex_aws: FakeAwsSuccess,
          monitor_pid: self()
        }

        logs =
          capture_log(fn ->
            # calls init() in Producer which allows for State overrides
            {:ok, _pid} = GenStage.start_link(FakeProducer, state: state_overrides)

            # allow above GenStage process to begin and process :initial_connection message
            Process.sleep(50)

            # confirm we made it through to subscribing to the shard
            assert called(
                     BroadwayKinesis.SubscribeToShard.subscribe(
                       "fake_consumer_arn",
                       "test-shard-0",
                       :latest,
                       []
                     )
                   )
          end)

        assert logs =~ "Initial Kinesis connection success"
      end
    end

    test "ExAws.request!() failure results in retry" do
      state_overrides = %{
        ex_aws: FakeAwsFail,
        monitor_pid: self()
      }

      logs =
        capture_log(fn ->
          # calls init() in Producer which allows for State overrides
          {:ok, _pid} = GenStage.start_link(FakeProducer, state: state_overrides)

          # confirm we receive {monitor_msg, error}, indicating retry_conn() is called
          assert_receive {:connection_error, %RuntimeError{message: "FakeAws request failure!"}},
                         1000
        end)

      assert logs =~ "Initial connection to Kinesis failed with exception:"
    end
  end
end
