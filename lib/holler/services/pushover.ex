defmodule Holler.Services.Pushover do
  @moduledoc """
  Pushover notification service for Holler.

  ## URL format

      pushover://shoutrrr:TOKEN@USERKEY/?devices=DEVICE1[,DEVICE2]

  ## Options (query parameters)

  | Key       | Default | Description |
  |-----------|---------|-------------|
  | `devices` | _(all)_ | Comma-separated device names |
  | `title`   | _(none)_| Notification title |
  | `priority`| `0`     | -1 (low), 0 (normal), 1 (high) |

  Note: priority 2 (emergency) is not supported as it requires extra parameters.

  ## Example

      pushover://shoutrrr:aToken123@aUserKey456/?devices=myphone&title=Alert&priority=1
  """

  @behaviour Holler.Service

  @api_url "https://api.pushover.net/1/messages.json"

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, token} <- parse_token(uri),
         {:ok, user_key} <- parse_user_key(uri) do
      query = parse_query(uri.query)

      devices =
        case query["devices"] do
          nil -> []
          "" -> []
          d -> String.split(d, ",", trim: true)
        end

      config = %{
        token: token,
        user_key: user_key,
        devices: devices,
        title: query["title"] || "",
        priority: parse_integer(query["priority"], 0)
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    message = Holler.Click.append(message, params)

    title = Map.get(params, :title, config.title)
    priority = Map.get(params, :priority, config.priority)
    devices = Map.get(params, :devices, config.devices)

    targets = if devices == [], do: [""], else: devices

    results =
      Enum.map(targets, fn device ->
        send_to_device(config.token, config.user_key, message, title, priority, device)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      err -> err
    end
  end

  # --- Private helpers ---

  defp parse_token(%URI{userinfo: nil}), do: {:error, :missing_token}
  defp parse_token(%URI{userinfo: ""}), do: {:error, :missing_token}

  defp parse_token(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [_prefix, token] when token != "" -> {:ok, token}
      _ -> {:error, :invalid_token_format}
    end
  end

  defp parse_user_key(%URI{host: nil}), do: {:error, :missing_user_key}
  defp parse_user_key(%URI{host: ""}), do: {:error, :missing_user_key}
  defp parse_user_key(%URI{host: user_key}), do: {:ok, user_key}

  defp send_to_device(token, user_key, message, title, priority, device) do
    payload =
      %{
        "token" => token,
        "user" => user_key,
        "message" => message,
        "priority" => priority
      }
      |> maybe_put("title", title)
      |> maybe_put("device", device)

    case Holler.HTTP.post(@api_url, json: payload) do
      {:ok, %{status: 200, body: %{"status" => 1}}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

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
