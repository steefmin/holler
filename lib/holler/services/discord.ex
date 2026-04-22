defmodule Holler.Services.Discord do
  @moduledoc """
  Discord notification service for Holler.

  Sends messages via a Discord incoming webhook.

  ## URL format

      discord://TOKEN@WEBHOOK_ID[?options]

  The `TOKEN` and `WEBHOOK_ID` come from your Discord webhook URL:
  `https://discord.com/api/webhooks/WEBHOOK_ID/TOKEN`

  ## Options (query parameters)

  | Key         | Default | Description |
  |-------------|---------|-------------|
  | `username`  | _(webhook default)_ | Override the display name |
  | `avatar`    | _(webhook default)_ | Override the avatar URL |
  | `thread_id` | _(none)_            | Post into a thread |

  ## Example

      discord://TOKEN@1234567890?username=Holler&thread_id=9876543210
  """

  @behaviour Holler.Service

  @api_base "https://discord.com/api/webhooks"

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, webhook_id} <- parse_webhook_id(uri),
         {:ok, token} <- parse_token(uri) do
      query = parse_query(uri.query)

      config = %{
        webhook_id: webhook_id,
        token: token,
        username: query["username"] || "",
        avatar: query["avatar"] || "",
        thread_id: query["thread_id"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    username = Map.get(params, :username, config.username)
    avatar = Map.get(params, :avatar, config.avatar)
    thread_id = Map.get(params, :thread_id, config.thread_id)

    url = build_url(config, thread_id)

    payload =
      %{"content" => message}
      |> maybe_put("username", username)
      |> maybe_put("avatar_url", avatar)

    case Req.post(url, json: payload) do
      {:ok, %{status: 204}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp parse_webhook_id(%URI{host: nil}), do: {:error, :missing_webhook_id}
  defp parse_webhook_id(%URI{host: ""}), do: {:error, :missing_webhook_id}
  defp parse_webhook_id(%URI{host: id}), do: {:ok, id}

  defp parse_token(%URI{userinfo: nil}), do: {:error, :missing_token}
  defp parse_token(%URI{userinfo: ""}), do: {:error, :missing_token}
  defp parse_token(%URI{userinfo: token}), do: {:ok, token}

  defp build_url(config, thread_id) do
    base = "#{@api_base}/#{config.webhook_id}/#{config.token}"

    if thread_id != "" do
      base <> "?thread_id=#{URI.encode_www_form(thread_id)}"
    else
      base
    end
  end

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
