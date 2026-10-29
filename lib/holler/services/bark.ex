defmodule Holler.Services.Bark do
  @moduledoc """
  Bark notification service for Holler.

  Sends push notifications to iOS devices via a Bark server.

  ## URL format

      bark://:DEVICEKEY@HOST[/PATH][?options]

  ## Options (query parameters)

  | Key        | Default  | Description |
  |------------|----------|-------------|
  | `title`    | _(none)_ | Notification title |
  | `scheme`   | `https`  | `http` or `https` |
  | `sound`    | _(none)_ | Sound name (see Bark sounds list) |
  | `group`    | _(none)_ | Notification group |
  | `icon`     | _(none)_ | URL to icon image (iOS 15+) |
  | `badge`    | `0`      | Number on app icon badge |
  | `url`      | _(none)_ | URL to open when notification is tapped |
  | `copy`     | _(none)_ | Value to copy to clipboard |
  | `category` | _(none)_ | Reserved for future use |

  `title` and `click` in `params` override `title` and `url` per message.

  ## Example

      bark://:mydevicekey@api.day.app?title=Alert&sound=chime
  """

  @behaviour Holler.Service

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, device_key} <- parse_device_key(uri),
         {:ok, host} <- parse_host(uri) do
      query = parse_query(uri.query)

      scheme =
        case query["scheme"] do
          "http" -> "http"
          _ -> "https"
        end

      path = String.trim_trailing(uri.path || "", "/")

      config = %{
        device_key: device_key,
        host: host,
        path: path,
        scheme: scheme,
        title: query["title"] || "",
        sound: query["sound"] || "",
        group: query["group"] || "",
        icon: query["icon"] || "",
        badge: parse_integer(query["badge"], 0),
        url: query["url"] || "",
        copy: query["copy"] || "",
        category: query["category"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    title = Map.get(params, :title, config.title)
    url = Map.get(params, :click, config.url)
    config = %{config | title: title, url: url}

    endpoint = "#{config.scheme}://#{config.host}#{config.path}/#{URI.encode(config.device_key)}"

    payload =
      %{"body" => message}
      |> maybe_put("title", config.title)
      |> maybe_put("sound", config.sound)
      |> maybe_put("group", config.group)
      |> maybe_put("icon", config.icon)
      |> maybe_put("url", config.url)
      |> maybe_put("copy", config.copy)
      |> maybe_put("category", config.category)
      |> then(fn m -> if config.badge > 0, do: Map.put(m, "badge", config.badge), else: m end)

    case Holler.HTTP.post(endpoint, json: payload) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp parse_device_key(%URI{userinfo: nil}), do: {:error, :missing_device_key}
  defp parse_device_key(%URI{userinfo: ""}), do: {:error, :missing_device_key}

  defp parse_device_key(%URI{userinfo: userinfo}) do
    # userinfo is ":devicekey" (password only, no username)
    case String.split(userinfo, ":", parts: 2) do
      [_, key] when key != "" -> {:ok, key}
      _ -> {:error, :invalid_device_key_format}
    end
  end

  defp parse_host(%URI{host: nil}), do: {:error, :missing_host}
  defp parse_host(%URI{host: ""}), do: {:error, :missing_host}
  defp parse_host(%URI{host: host}), do: {:ok, host}

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_integer(nil, default), do: default

  defp parse_integer(value, default) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
