defmodule Holler.Services.Mattermost do
  @moduledoc """
  Mattermost notification service for Holler.

  Sends messages via a Mattermost incoming webhook.

  ## URL format

      mattermost://[USERNAME@]HOST[:PORT]/TOKEN[/CHANNEL][?icon=ICON]

  ## Options (query parameters)

  | Key    | Default  | Description |
  |--------|----------|-------------|
  | `icon` | _(none)_ | Emoji (`:smile:`) or URL for bot icon |

  Override params also accepted: `username`, `channel`, `icon`.

  ## Examples

      mattermost://my-server.com/abc123def456
      mattermost://shoutrrrUser@my-server.com/abc123def456/general?icon=:robot:
  """

  @behaviour Holler.Service

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, host} <- parse_host(uri),
         {:ok, {token, channel}} <- parse_path(uri) do
      query = parse_query(uri.query)

      config = %{
        host: host,
        port: uri.port,
        token: token,
        channel: channel,
        username: uri.userinfo || "",
        icon: query["icon"] || query["icon_emoji"] || query["icon_url"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    message = Holler.Click.append(message, params)

    username = Map.get(params, :username, config.username)
    channel = Map.get(params, :channel, config.channel)
    icon = Map.get(params, :icon, config.icon)

    url = build_url(config)

    payload =
      %{"text" => message}
      |> maybe_put("username", username)
      |> maybe_put("channel", channel)
      |> put_icon(icon)

    case Holler.HTTP.post(url, json: payload) do
      {:ok, %{status: 200}} ->
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
      [token] -> {:ok, {token, ""}}
      [token, channel] -> {:ok, {token, channel}}
      _ -> {:error, :invalid_path}
    end
  end

  defp build_url(config) do
    port_part = if config.port, do: ":#{config.port}", else: ""
    "https://#{config.host}#{port_part}/hooks/#{config.token}"
  end

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp put_icon(payload, ""), do: payload

  defp put_icon(payload, icon) do
    if Regex.match?(~r/^https?:\/\//, icon) do
      Map.put(payload, "icon_url", icon)
    else
      Map.put(payload, "icon_emoji", icon)
    end
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
