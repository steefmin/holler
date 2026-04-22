defmodule Holler.Services.Zulip do
  @moduledoc """
  Zulip Chat notification service for Holler.

  Sends messages via the Zulip bot API.

  ## URL format

      zulip://BOTMAIL:BOTKEY@HOST[:PORT]/?stream=STREAM&topic=TOPIC

  Note: Since `BOTMAIL` contains `@`, you must URL-encode it as `%40`.

  ## Options (query parameters)

  | Key      | Default  | Description |
  |----------|----------|-------------|
  | `stream` | _(none)_ | Stream (channel) name or ID |
  | `topic`  | _(none)_ | Topic (alias: `title`) |

  ## Examples

      zulip://my-bot%40zulipchat.com:apikey@org.zulipchat.com/?stream=general&topic=Alerts
      zulip://my-bot%40zulipchat.com:apikey@org.zulipchat.com/
  """

  @behaviour Holler.Service

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, host} <- parse_host(uri),
         {:ok, {bot_mail, bot_key}} <- parse_credentials(uri) do
      query = parse_query(uri.query)

      config = %{
        host: host,
        port: uri.port,
        bot_mail: bot_mail,
        bot_key: bot_key,
        stream: query["stream"] || "",
        topic: query["topic"] || query["title"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    stream = Map.get(params, :stream, config.stream)
    topic = Map.get(params, :topic, Map.get(params, :title, config.topic))

    port_part = if config.port, do: ":#{config.port}", else: ""
    url = "https://#{config.host}#{port_part}/api/v1/messages"

    {msg_type, payload} =
      if stream != "" do
        {"stream",
         %{
           "type" => "stream",
           "to" => stream,
           "topic" => topic,
           "content" => message
         }}
      else
        {"private",
         %{
           "type" => "private",
           "to" => config.bot_mail,
           "content" => message
         }}
      end

    _ = msg_type

    case Req.post(url,
           form: payload,
           auth: {:basic, "#{config.bot_mail}:#{config.bot_key}"}
         ) do
      {:ok, %{status: 200, body: %{"result" => "success"}}} ->
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

  defp parse_credentials(%URI{userinfo: nil}), do: {:error, :missing_credentials}
  defp parse_credentials(%URI{userinfo: ""}), do: {:error, :missing_credentials}

  defp parse_credentials(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [mail, key] when mail != "" and key != "" -> {:ok, {mail, key}}
      _ -> {:error, :invalid_credentials}
    end
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
