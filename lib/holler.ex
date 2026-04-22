defmodule Holler do
  @moduledoc """
  Holler — a notification library with URL-based configuration.

  ## Sending to a single service

      Holler.send("gotify://hostname/AqEtoken123456", "Hello!")

  ## Multiple services (reusable sender)

      {:ok, sender} = Holler.create_sender([
        "gotify://host1/AqEtoken123456",
        "gotify://host2/BqFtoken654321"
      ])
      Holler.Sender.send(sender, "Hello!")
  """

  @doc """
  Sends a message via a single URL.
  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec send(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def send(url, message, params \\ %{}) do
    Holler.Router.route(url, message, params)
  end

  @doc """
  Creates a `Holler.Sender` from a list of URL strings.
  Returns `{:ok, sender}`, or `{:error, {url, reason}}` on failure.
  """
  @spec create_sender([String.t()]) :: {:ok, Holler.Sender.t()} | {:error, {String.t(), term()}}
  def create_sender(urls) when is_list(urls) do
    Holler.Sender.new(urls)
  end
end
