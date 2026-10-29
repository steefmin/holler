defmodule Holler.Services.Slack do
  @moduledoc """
  Slack notification service for Holler.

  Supports both incoming webhook and Bot API token modes.

  ## URL formats

  ### Webhook (modern)

      slack://hook:TXXXXXXXXX/BXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX

  ### Webhook (legacy — token spread across host and path)

      slack://TXXXXXXXXX/BXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX

  ### Bot API

      slack://xoxb:TXXXXXXXXX-BXXXXXXXXX-XXXXXXXXXXXXXXXXXXXXXXXX@CXXXXXXXXXX

  ## Optional query parameters

  | Key         | Description                              | Default |
  |-------------|------------------------------------------|---------|
  | `bot_name`  | Display name of the bot                  | Slack default |
  | `icon`      | Emoji (`:robot:`) or URL for bot icon    | Slack default |
  | `color`     | Left-border colour of the attachment     | none |
  | `title`     | Text prepended above the message         | none |
  | `thread_ts` | Parent message timestamp (for replies)   | none |

  ## Examples

      slack://hook:TXXXXXXXXX/BXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX
      slack://xoxb:TXXXXXXXXX-BXXXXXXXXX-XXXXXXXXXXXXXXXXXXXXXXXX@CXXXXXXXXXX?title=Alert&color=#ff0000
  """

  @behaviour Holler.Service

  @api_url "https://slack.com/api/chat.postMessage"
  @webhook_base "https://hooks.slack.com/services/"
  @max_attachments 100

  # Matches:  [type:] part1 sep part2 sep part3
  # type      = xox? (xoxb, xoxp, xoxe, …) or "hook"  (optional)
  # part1/2   = 9+ uppercase alphanumeric chars
  # sep       = - / or , (must be identical for both separators)
  # part3     = 24+ alphanumeric chars (mixed case)
  @token_regex ~r/^(?:(?P<type>xox.|hook)[-:])?(?P<p1>[A-Z0-9]{9,})(?P<s1>[-\/,])(?P<p2>[A-Z0-9]{9,})(?P<s2>[-\/,])(?P<p3>[A-Za-z0-9]{24,})$/

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, raw_token, channel} <- extract_token_and_channel(uri),
         {:ok, token} <- parse_token(raw_token) do
      query = parse_query(uri.query)

      config = %{
        token: token,
        channel: channel,
        mode: token_mode(token.type),
        bot_name: query["bot_name"] || query["username"] || "",
        icon: query["icon"] || query["icon_emoji"] || query["icon_url"] || "",
        color: query["color"] || "",
        title: query["title"] || "",
        thread_ts: query["thread_ts"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    message = Holler.Click.append(message, params)

    config = merge_params(config, params)
    payload = build_payload(config, message)

    case config.mode do
      :webhook -> send_webhook(config, payload)
      :api -> send_api(config, payload)
    end
  end

  # --- Payload building ---

  @doc false
  def build_payload(config, message) do
    attachments = build_attachments(message, config.color)

    payload = %{
      "text" => config.title,
      "username" => config.bot_name,
      "thread_ts" => config.thread_ts,
      "attachments" => attachments
    }

    payload =
      if config.channel != "" and config.channel != "webhook" do
        Map.put(payload, "channel", config.channel)
      else
        payload
      end

    set_icon(payload, config.icon)
  end

  # --- Private helpers ---

  # Modern format: userinfo present  →  "type:part1-part2-part3"@channel
  # Legacy format: no userinfo       →  host/part1/part2/part3  (all in host+path)
  defp extract_token_and_channel(%URI{userinfo: userinfo, host: host})
       when is_binary(userinfo) and userinfo != "" do
    {:ok, userinfo, host || ""}
  end

  defp extract_token_and_channel(%URI{host: host, path: path}) do
    # Legacy: the token parts are spread over host and path segments
    # e.g. host="TXXXXXXXXX", path="/BXXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX"
    parts = [host | String.split(path || "", "/", trim: true)]

    case parts do
      [p1, p2, p3] -> {:ok, "#{p1}/#{p2}/#{p3}", "webhook"}
      _ -> {:error, :invalid_token}
    end
  end

  defp parse_token(raw) do
    case Regex.named_captures(@token_regex, raw) do
      nil ->
        {:error, :invalid_token}

      %{"s1" => s1, "s2" => s2} when s1 != s2 ->
        {:error, :mismatched_token_separators}

      %{"type" => type, "p1" => p1, "s1" => sep, "p2" => p2, "p3" => p3} ->
        normalized_type = if type == "", do: "hook", else: type

        token = %{
          type: normalized_type,
          p1: p1,
          p2: p2,
          p3: p3,
          sep: sep
        }

        {:ok, token}
    end
  end

  defp token_mode("hook"), do: :webhook
  defp token_mode(_type), do: :api

  defp webhook_url(%{p1: p1, p2: p2, p3: p3}) do
    @webhook_base <> p1 <> "/" <> p2 <> "/" <> p3
  end

  defp authorization(%{type: type, p1: p1, p2: p2, p3: p3}) do
    "Bearer #{type}-#{p1}-#{p2}-#{p3}"
  end

  defp build_attachments(message, color) do
    lines = String.split(message, "\n")
    {first, overflow} = Enum.split(lines, @max_attachments)

    atts = Enum.map(first, fn line -> %{"text" => line, "color" => color} end)

    atts =
      case overflow do
        [] ->
          atts

        _ ->
          overflow_text = Enum.join(overflow, "\n")

          List.update_at(atts, -1, fn att ->
            Map.update!(att, "text", &(&1 <> "\n" <> overflow_text))
          end)
      end

    remove_trailing_empty(atts)
  end

  defp remove_trailing_empty([]), do: []

  defp remove_trailing_empty(atts) do
    if List.last(atts)["text"] == "" do
      Enum.drop(atts, -1)
    else
      atts
    end
  end

  defp set_icon(payload, ""), do: payload

  defp set_icon(payload, icon) do
    if Regex.match?(~r/^https?:\/\//, icon) do
      Map.put(payload, "icon_url", icon)
    else
      Map.put(payload, "icon_emoji", icon)
    end
  end

  defp send_webhook(config, payload) do
    url = webhook_url(config.token)

    case Holler.HTTP.post(url, json: payload) do
      {:ok, %{status: 200, body: "ok"}} ->
        :ok

      {:ok, %{status: 200, body: ""}} ->
        :ok

      {:ok, %{status: 200, body: body}} ->
        {:error, {:webhook_error, body}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp send_api(config, payload) do
    auth = authorization(config.token)

    case Holler.HTTP.post(@api_url, json: payload, headers: [{"authorization", auth}]) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        :ok

      {:ok, %{status: 200, body: %{"ok" => false, "error" => err}}} ->
        {:error, {:api_error, err}}

      {:ok, %{status: 200, body: _}} ->
        {:error, :unknown_api_error}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)

  defp merge_params(config, params) when map_size(params) == 0, do: config

  defp merge_params(config, params) do
    Enum.reduce(params, config, fn {key, val}, acc ->
      key_str = if is_atom(key), do: Atom.to_string(key), else: key

      try do
        atom_key = String.to_existing_atom(key_str)

        if Map.has_key?(acc, atom_key) do
          Map.put(acc, atom_key, val)
        else
          acc
        end
      rescue
        ArgumentError -> acc
      end
    end)
  end
end
