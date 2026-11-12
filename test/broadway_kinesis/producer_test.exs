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

  defmodule FakeProducerWithInitialStateFn do
    use BroadwayKinesis.Logger

    use BroadwayKinesis.Producer,
      consumer_arn: "fake_consumer_arn",
      stream_name: "fake_stream_name",
      initial_state_fn: fn -> %{subscribe_opts: [foo: :bar]} end
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

  describe "liveness checks" do
    test "forces a reconnect when no events arrive within the liveness_timeout" do
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
          monitor_pid: self(),
          liveness_check_interval: 10,
          liveness_timeout: 10
        }

        logs =
          capture_log(fn ->
            {:ok, _pid} = GenStage.start_link(FakeProducer, state: state_overrides)

            # the liveness check fires ~10ms after connecting, finds no events have
            # arrived since, and forces a reconnection via retry_conn/4
            assert_receive {:liveness_timeout, :liveness_timeout_exceeded}, 1000
          end)

        assert logs =~ "event=liveness_timeout"
      end
    end

    test "reschedules the check without reconnecting while the connection stays alive" do
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
          monitor_pid: self(),
          liveness_check_interval: 10,
          liveness_timeout: 1000
        }

        capture_log(fn ->
          {:ok, _pid} = GenStage.start_link(FakeProducer, state: state_overrides)

          # several checks fire well within the liveness_timeout, so no reconnect
          # should be triggered
          refute_receive {:liveness_timeout, _}, 100
        end)
      end
    end

    test "a freshly received event resets the clock, avoiding a false reconnect" do
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
          monitor_pid: self(),
          liveness_check_interval: 40,
          liveness_timeout: 70
        }

        capture_log(fn ->
          {:ok, pid} = GenStage.start_link(FakeProducer, state: state_overrides)

          # Simulate a (possibly empty) event arriving partway through the first
          # liveness_check_interval, which is what the main streaming handle_info
          # clause would do by updating last_event_at. This is done directly via
          # :sys.replace_state since the mocked conn (a bare atom) can't satisfy
          # the is_message/2 guard needed to drive a real message through.
          Process.sleep(25)

          :sys.replace_state(pid, fn full_state ->
            update_in(full_state.state.last_event_at, fn _ ->
              System.monotonic_time(:millisecond)
            end)
          end)

          # By the second check (~80ms after the original connection), elapsed
          # time since the *original* connection would exceed liveness_timeout
          # (70ms), which would have forced a reconnect. Because last_event_at
          # was refreshed at ~25ms, the connection is correctly treated as alive
          # through this check (elapsed ~55ms < 70ms).
          refute_receive {:liveness_timeout, _}, 70

          assert %{state: %{conn_state: :established}} = :sys.get_state(pid)
        end)
      end
    end

    test "ignores a stale liveness check while a reconnection is already pending" do
      state_overrides = %{
        ex_aws: FakeAwsFail,
        monitor_pid: self()
      }

      capture_log(fn ->
        {:ok, pid} = GenStage.start_link(FakeProducer, state: state_overrides)

        assert_receive {:connection_error, %RuntimeError{message: "FakeAws request failure!"}},
                       1000

        send(pid, :liveness_check)

        refute_receive {:liveness_timeout, _}, 200
        assert %{state: %{conn_state: :retry}} = :sys.get_state(pid)
      end)
    end
  end

  describe "initial_state_fn" do
    test "accepts initial_state_fn/0 callback" do
      old_log_level = Logger.level()

      on_exit(fn -> Logger.configure(level: old_log_level) end)

      Logger.configure(level: :warning)

      {:ok, _pid} =
        start_supervised(
          {ProducerRegistry,
           [name: BroadwayKinesis.ProducerRegistry, registry_name: :test_registry]},
          restart: :temporary
        )

      with_mock BroadwayKinesis.SubscribeToShard,
        subscribe: fn _arn, _shard, _pos, _opts -> {:ok, :conn} end do
        {:ok, pid} =
          GenStage.start_link(FakeProducerWithInitialStateFn,
            state: %{ex_aws: FakeAwsSuccess, monitor_pid: self()}
          )

        assert %{state: %{subscribe_opts: [foo: :bar]}} = :sys.get_state(pid)
      end
    end
  end
end
