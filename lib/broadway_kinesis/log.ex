defmodule BroadwayKinesis.Logger do
  defmacro __using__(_) do
    quote do
      require Logger
      defp log(message), do: Logger.info("#{__MODULE__}: #{message}")
      defp warn(message), do: Logger.warning("#{__MODULE__}: #{message}")
      defp error(message), do: Logger.error("#{__MODULE__}: #{message}")
    end
  end
end
