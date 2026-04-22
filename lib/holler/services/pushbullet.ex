defmodule Holler.Services.Pushbullet do
  @moduledoc """
  Pushbullet notification service for Holler.

  Sends push notifications via the Pushbullet API.

  ## URL format

      pushbullet://TOKEN[/TARGET]

  The TARGET can be:
  - A device identifier
  - `#CHANNEL` for a channel
  - An email address

  If no target is given, the push is sent to all devices.

  ## Options (query parameters)

  | Key     | Default                  | Description |
  |---------|--------------------------|-------------|
  | `title` | `Holler notification`    | Notification title |

  ## Examples

      pushbullet://myapitoken
      pushbullet://myapitoken/mydevice
      pushbullet://myapitoken/#mychannel
      pushbullet://myapitoken/user@example.com
  """

  @behaviour Holler.Service

  @api_url "https://api.pushbullet.com/v2/pushes"
  @default_title "Holler notification"

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, token} <- parse_token(uri) do
      query = parse_query(uri.query)
      target = parse_target(uri)

      config = %{
        token: token,
        target: target,
        title: query["title"] || @default_title
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    title = Map.get(params, :title, config.title)

    payload =
      %{
        "type" => "note",
        "title" => title,
        "body" => message
      }
      |> apply_target(config.target)

    case Req.post(@api_url,
           json: payload,
           headers: [{"access-token", config.token}]
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp parse_token(%URI{host: nil}), do: {:error, :missing_token}
  defp parse_token(%URI{host: ""}), do: {:error, :missing_token}
  defp parse_token(%URI{host: token}), do: {:ok, token}

  defp parse_target(%URI{path: nil}), do: nil
  defp parse_target(%URI{path: ""}), do: nil
  defp parse_target(%URI{path: "/"}), do: nil

  defp parse_target(%URI{path: path}) do
    target = String.trim_leading(path, "/")
    if target == "", do: nil, else: target
  end

  defp apply_target(payload, nil), do: payload

  defp apply_target(payload, "#" <> channel),
    do: Map.put(payload, "channel_tag", channel)

  defp apply_target(payload, target) do
    if String.contains?(target, "@") do
      Map.put(payload, "email", target)
    else
      Map.put(payload, "device_iden", target)
    end
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
