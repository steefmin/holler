defmodule Holler.Services.Mercure do
  @moduledoc """
  Mercure notification service for Holler.

  Publishes updates to a [Mercure hub](https://mercure.rocks) via HTTP POST.
  Subscribers connected to the hub (browsers, apps) receive the update in
  real-time over Server-Sent Events.

  The JWT must be a signed JWS containing a `mercure.publish` claim with an
  array of topic selectors that covers the topic you want to publish to.
  Because the JWT is sensitive, it is passed as the password in the URL
  userinfo component — keep URLs out of logs and plaintext storage.

  ## URL format

      mercure://:JWT@HOST[:PORT][/subpath]?topic=TOPIC_IRI[&options]

  The hub endpoint is always `/.well-known/mercure` appended to the host
  (and optional subpath).

  ## Options (query parameters)

  | Key          | Default  | Description |
  |--------------|----------|-------------|
  | `topic`      | *(required)* | Topic IRI to publish to |
  | `disabletls` | `no`     | Use `http` instead of `https` |
  | `private`    | `no`     | Mark update as private (`on`) |
  | `id`         | *(hub generates)* | Custom event ID (IRI) |
  | `type`       | *(none)_ | SSE event type |
  | `retry`      | *(none)_ | SSE reconnection time in milliseconds |

  ## Examples

      mercure://:eyJhbGci...@example.com?topic=https://example.com/books/1
      mercure://:eyJhbGci...@example.com:3000?topic=https://example.com/notify&private=yes
      mercure://:eyJhbGci...@localhost?topic=https://example.com/events&disabletls=yes
  """

  @behaviour Holler.Service

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, host} <- parse_host(uri),
         {:ok, jwt} <- parse_jwt(uri),
         {:ok, topic} <- parse_topic(uri) do
      query = parse_query(uri.query)
      disable_tls = query["disabletls"] in ["yes", "true", "1"]
      private = query["private"] in ["yes", "true", "1", "on"]

      hub_path = String.trim_trailing(uri.path || "", "/")

      config = %{
        host: host,
        port: uri.port,
        jwt: jwt,
        topic: topic,
        hub_path: hub_path,
        disable_tls: disable_tls,
        private: private,
        id: query["id"] || "",
        type: query["type"] || "",
        retry: query["retry"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    message = Holler.Click.append(message, params)

    topic = Map.get(params, :topic, config.topic)
    private = Map.get(params, :private, config.private)
    id = Map.get(params, :id, config.id)
    type = Map.get(params, :type, config.type)
    retry = Map.get(params, :retry, config.retry)

    url = build_url(config)

    body =
      [{"topic", topic}, {"data", message}]
      |> maybe_field("private", if(private, do: "on", else: ""))
      |> maybe_field("id", id)
      |> maybe_field("type", type)
      |> maybe_field("retry", to_string_or_empty(retry))

    case Holler.HTTP.post(url,
           form: body,
           headers: [{"authorization", "Bearer #{config.jwt}"}]
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp parse_host(%URI{host: nil}), do: {:error, :missing_host}
  defp parse_host(%URI{host: ""}), do: {:error, :missing_host}
  defp parse_host(%URI{host: host}), do: {:ok, host}

  defp parse_jwt(%URI{userinfo: nil}), do: {:error, :missing_jwt}
  defp parse_jwt(%URI{userinfo: ""}), do: {:error, :missing_jwt}

  defp parse_jwt(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [_, jwt] when jwt != "" -> {:ok, jwt}
      _ -> {:error, :missing_jwt}
    end
  end

  defp parse_topic(%URI{query: nil}), do: {:error, :missing_topic}

  defp parse_topic(%URI{query: query}) do
    case URI.decode_query(query)["topic"] do
      nil -> {:error, :missing_topic}
      "" -> {:error, :missing_topic}
      topic -> {:ok, topic}
    end
  end

  defp build_url(config) do
    scheme = if config.disable_tls, do: "http", else: "https"
    port_part = if config.port, do: ":#{config.port}", else: ""
    "#{scheme}://#{config.host}#{port_part}#{config.hub_path}/.well-known/mercure"
  end

  defp maybe_field(fields, _key, ""), do: fields
  defp maybe_field(fields, key, value), do: [{key, value} | fields]

  defp to_string_or_empty(v) when is_integer(v), do: Integer.to_string(v)
  defp to_string_or_empty(v) when is_binary(v), do: v
  defp to_string_or_empty(_), do: ""

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
