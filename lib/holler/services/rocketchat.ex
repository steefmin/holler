defmodule Holler.Services.Rocketchat do
  @moduledoc """
  Rocket.Chat notification service for Holler.

  Sends messages via a Rocket.Chat incoming webhook.

  ## URL format

      rocketchat://[USERNAME@]HOST[:PORT]/TOKENA/TOKENB/CHANNEL

  The two token parts come from the webhook URL:

      https://your-domain.com/hooks/TOKENA/TOKENB

  ## Examples

      rocketchat://my-server.com/8eGdRzc9r4YYNyvge/2XYQcX9NBwJBK/general
      rocketchat://shoutrrrUser@my-server.com:3000/8eGdRzc9r4YYNyvge/2XYQcX9NBwJBK/@alice
  """

  @behaviour Holler.Service

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, host} <- parse_host(uri),
         {:ok, {token_a, token_b, channel}} <- parse_path(uri) do
      config = %{
        host: host,
        port: uri.port,
        username: uri.userinfo || "",
        token_a: token_a,
        token_b: token_b,
        channel: channel
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    username = Map.get(params, :username, config.username)
    channel = Map.get(params, :channel, config.channel)

    url = build_url(config)

    payload =
      %{"text" => message}
      |> maybe_put("username", username)
      |> maybe_put("channel", channel)

    case Req.post(url, json: payload) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp parse_host(%URI{host: nil}), do: {:error, :missing_host}
  defp parse_host(%URI{host: ""}), do: {:error, :missing_host}
  defp parse_host(%URI{host: host}), do: {:ok, host}

  defp parse_path(%URI{path: nil}), do: {:error, :missing_token}
  defp parse_path(%URI{path: ""}), do: {:error, :missing_token}

  defp parse_path(%URI{path: path}) do
    segments = String.split(path, "/", trim: true)

    case segments do
      [token_a, token_b, channel] -> {:ok, {token_a, token_b, channel}}
      _ -> {:error, :invalid_path}
    end
  end

  defp build_url(config) do
    port_part = if config.port, do: ":#{config.port}", else: ""
    "https://#{config.host}#{port_part}/hooks/#{config.token_a}/#{config.token_b}"
  end

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
