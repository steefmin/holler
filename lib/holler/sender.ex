defmodule Holler.Sender do
  @moduledoc """
  Holds a list of initialised services for reuse.
  Sends messages concurrently to all services via `Task.async_stream`.
  """

  @default_timeout 5_000

  @enforce_keys [:services]
  defstruct services: []

  @type t :: %__MODULE__{
          services: [{module(), map()}]
        }

  @doc """
  Creates a new `Sender` from a list of URL strings.
  Returns `{:ok, sender}`, or `{:error, {url, reason}}` if any URL fails.
  """
  @spec new([String.t()]) :: {:ok, t()} | {:error, {String.t(), term()}}
  def new(urls) when is_list(urls) do
    urls
    |> Enum.reduce_while({:ok, []}, fn url, {:ok, acc} ->
      case Holler.Router.locate(url) do
        {:ok, service} -> {:cont, {:ok, [service | acc]}}
        {:error, reason} -> {:halt, {:error, {url, reason}}}
      end
    end)
    |> case do
      {:ok, services} -> {:ok, %__MODULE__{services: Enum.reverse(services)}}
      {:error, _} = err -> err
    end
  end

  @doc """
  Sends a message to all services in the sender.
  Returns a list of `:ok | {:error, term()}` — one per service.
  """
  @spec send(t(), String.t(), map(), keyword()) :: [:ok | {:error, term()}]
  def send(%__MODULE__{services: services}, message, params \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    services
    |> Task.async_stream(
      fn {module, config} -> module.send(config, message, params) end,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {:error, :timeout}
      {:exit, reason} -> {:error, {:exit, reason}}
    end)
  end
end
