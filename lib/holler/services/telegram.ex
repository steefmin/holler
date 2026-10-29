defmodule Holler.Services.Telegram do
  @moduledoc """
  Telegram notification service for Holler.

  Sends messages via the Telegram Bot API to one or more chats.

  ## URL format

      telegram://BOT_ID:TOKEN@telegram?chats=CHAT_ID[&options]

  The `BOT_ID:TOKEN` is the full bot token from BotFather
  (e.g. `123456789:AABBccddEEFFggHH...`).

  Multiple chats can be specified as a comma-separated list:

      telegram://BOT_ID:TOKEN@telegram?chats=111,222,@mychannel

  ## Options (query parameters)

  | Key            | Default | Description |
  |----------------|---------|-------------|
  | `chats`        | _(required)_ | Comma-separated chat IDs or `@channel` names |
  | `parsemode`    | `None`  | `None`, `HTML`, `Markdown`, or `MarkdownV2` |
  | `preview`      | `yes`   | Show link previews |
  | `notification` | `yes`   | Send with sound/notification |
  | `title`        | _(none)_| Prepended as bold text (forces `HTML` parse mode) |

  ## Examples

      telegram://123456789:AABBccdd@telegram?chats=-100123456789
      telegram://123456789:AABBccdd@telegram?chats=@mychannel&parsemode=HTML&title=Alert
  """

  @behaviour Holler.Service

  @api_base "https://api.telegram.org/bot"
  @max_length 4096
  @valid_parse_modes ~w(None HTML Markdown MarkdownV2)

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, token} <- parse_token(uri),
         {:ok, chats} <- parse_chats(uri) do
      query = parse_query(uri.query)
      parse_mode = validate_parse_mode(query["parsemode"] || "None")

      config = %{
        token: token,
        chats: chats,
        parse_mode: parse_mode,
        preview: query["preview"] not in ["no", "false", "0"],
        notification: query["notification"] not in ["no", "false", "0"],
        title: query["title"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    message = Holler.Click.append(message, params)

    if String.length(message) > @max_length do
      {:error, :message_too_long}
    else
      title = Map.get(params, :title, config.title)
      config = %{config | title: title}

      results =
        Enum.map(config.chats, fn chat ->
          send_to_chat(config, message, chat)
        end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> :ok
        err -> err
      end
    end
  end

  # --- Private helpers ---

  defp parse_token(%URI{userinfo: nil}), do: {:error, :missing_token}
  defp parse_token(%URI{userinfo: ""}), do: {:error, :missing_token}

  defp parse_token(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":") do
      [_id, _token] -> {:ok, userinfo}
      _ -> {:error, :invalid_token_format}
    end
  end

  defp parse_chats(%URI{query: nil}), do: {:error, :missing_chats}

  defp parse_chats(%URI{query: query}) do
    params = URI.decode_query(query)

    case params["chats"] || params["channels"] do
      nil ->
        {:error, :missing_chats}

      "" ->
        {:error, :missing_chats}

      chats_str ->
        chats =
          chats_str
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)

        {:ok, chats}
    end
  end

  defp validate_parse_mode(mode) when mode in @valid_parse_modes, do: mode
  defp validate_parse_mode(_), do: "None"

  defp send_to_chat(config, message, chat) do
    {text, parse_mode} = build_text(config, message)
    url = "#{@api_base}#{config.token}/sendMessage"

    payload =
      %{
        "chat_id" => chat,
        "text" => text,
        "disable_web_page_preview" => !config.preview,
        "disable_notification" => !config.notification
      }
      |> maybe_put_parse_mode(parse_mode)

    case Holler.HTTP.post(url, json: payload) do
      {:ok, %{status: 200, body: %{"ok" => true}}} ->
        :ok

      {:ok, %{status: _, body: %{"ok" => false, "description" => desc}}} ->
        {:error, {:api_error, desc}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # When a title is set with no parse mode, force HTML and escape both
  defp build_text(%{title: title, parse_mode: "None"}, message) when title != "" do
    escaped_title = html_escape(title)
    escaped_msg = html_escape(message)
    {"<b>#{escaped_title}</b>\n#{escaped_msg}", "HTML"}
  end

  # With an explicit parse mode and a title, prepend the title
  defp build_text(%{title: title, parse_mode: parse_mode}, message) when title != "" do
    escaped_title = html_escape(title)
    {"<b>#{escaped_title}</b>\n#{message}", parse_mode}
  end

  defp build_text(%{parse_mode: parse_mode}, message) do
    {message, parse_mode}
  end

  defp maybe_put_parse_mode(payload, "None"), do: payload
  defp maybe_put_parse_mode(payload, mode), do: Map.put(payload, "parse_mode", mode)

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
