def module BroadwayKinesis.ProducerTest do
  alias BroadwayKinesis.ProducerRegistry
  alias BroadwayKinesis.Producer

  describe "initial Kinesis connection" do
    test "failure results in retry" do
      # TODO: unit test for asserting retry_conn() is called when initial Kinesis connection fails
    end
  end
end
