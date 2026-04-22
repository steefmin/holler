defmodule Holler.Service do
  @moduledoc """
  Behaviour that every notification service must implement.
  """

  @doc """
  Initialises a service config based on a parsed URI.
  Returns `{:ok, config}` on success, `{:error, reason}` on failure.
  """
  @callback initialize(URI.t()) :: {:ok, config :: map()} | {:error, term()}

  @doc """
  Sends a message via the service.
  `params` may contain service-specific options (e.g. title, priority).
  """
  @callback send(config :: map(), message :: String.t(), params :: map()) ::
              :ok | {:error, term()}
end
