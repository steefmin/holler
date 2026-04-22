defmodule Holler.Services.Join do
  @moduledoc """
  Join notification service for Holler.

  Sends push notifications via the Join API.

  ## URL format

      join://shoutrrr:APIKEY@join/?devices=DEVICE1[,DEVICE2][&icon=ICON_URL][&title=TITLE]

  ## Options (query parameters)

  | Key       | Default      | Description |
  |-----------|--------------|-------------|
  | `devices` | _(required)_ | Comma-separated device IDs |
  | `title`   | _(none)_     | Creates a notification with a title |
  | `icon`    | _(none)_     | Icon URL |

  ## Example

      join://shoutrrr:myapikey@join/?devices=device1,device2&title=Alert
  """

  @behaviour Holler.Service

  @api_base "https://joinjoaomgcd.appspot.com/_ah/api/messaging/v1/sendPush"

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, api_key} <- parse_api_key(uri),
         {:ok, devices} <- parse_devices(uri) do
      query = parse_query(uri.query)

      config = %{
        api_key: api_key,
        devices: devices,
        title: query["title"] || "",
        icon: query["icon"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    title = Map.get(params, :title, config.title)
    icon = Map.get(params, :icon, config.icon)

    query_params =
      [
        apikey: config.api_key,
        text: message,
        deviceIds: Enum.join(config.devices, ",")
      ]
      |> maybe_param(:title, title)
      |> maybe_param(:icon, icon)

    case Req.get(@api_base, params: query_params) do
      {:ok, %{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %{status: 200, body: %{"success" => false, "errorMessage" => msg}}} ->
        {:error, {:api_error, msg}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp parse_api_key(%URI{userinfo: nil}), do: {:error, :missing_api_key}
  defp parse_api_key(%URI{userinfo: ""}), do: {:error, :missing_api_key}

  defp parse_api_key(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [_prefix, key] when key != "" -> {:ok, key}
      _ -> {:error, :invalid_api_key_format}
    end
  end

  defp parse_devices(%URI{query: nil}), do: {:error, :missing_devices}

  defp parse_devices(%URI{query: query}) do
    params = URI.decode_query(query)

    case params["devices"] do
      nil -> {:error, :missing_devices}
      "" -> {:error, :missing_devices}
      d -> {:ok, String.split(d, ",", trim: true)}
    end
  end

  defp maybe_param(params, _key, ""), do: params
  defp maybe_param(params, key, value), do: [{key, value} | params]

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
