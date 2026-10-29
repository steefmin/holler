defmodule Holler.Services.Ntfy do
  @moduledoc """
  Ntfy notification service for Holler.

  Sends messages to an ntfy server (default: ntfy.sh) via HTTP.
  All metadata is passed as HTTP headers, matching the ntfy publish API.

  ## URL format

      ntfy://[user:password@]host/topic[?options]

  Omit the host to use the public `ntfy.sh` server:

      ntfy://ntfy.sh/my-topic
      ntfy://my-ntfy-server.com/alerts?title=Alert&priority=high

  ## Options (query parameters)

  | Key        | Default     | Description |
  |------------|-------------|-------------|
  | `title`    | _(none)_    | Notification title |
  | `priority` | `default`   | `min`, `low`, `default`, `high`, or `max` (also 1–5) |
  | `tags`     | _(none)_    | Comma-separated tags or emoji shortcodes |
  | `click`    | _(none)_    | URL to open when notification is clicked |
  | `attach`   | _(none)_    | URL of an attachment |
  | `filename` | _(none)_    | Filename for the attachment |
  | `icon`     | _(none)_    | URL to use as notification icon |
  | `email`    | _(none)_    | E-mail address for e-mail forwarding |
  | `delay`    | _(none)_    | Scheduled delivery (duration or timestamp) |
  | `cache`    | `yes`       | Cache message on server |
  | `firebase` | `yes`       | Forward to Firebase |
  | `scheme`   | `https`     | `http` or `https` |

  `title` and `click` in `params` override the matching options per message.

  ## Examples

      ntfy://ntfy.sh/my-topic
      ntfy://ntfy.sh/my-topic?title=Alert&priority=high&tags=warning
      ntfy://user:pass@my-server.com/alerts?scheme=http
  """

  @behaviour Holler.Service

  @valid_priorities ~w(min low default high max 1 2 3 4 5)

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, host} <- parse_host(uri),
         {:ok, topic} <- parse_topic(uri) do
      query = parse_query(uri.query)
      {username, password} = parse_credentials(uri)

      scheme =
        case query["scheme"] do
          "http" -> "http"
          _ -> "https"
        end

      config = %{
        host: host,
        topic: topic,
        username: username,
        password: password,
        scheme: scheme,
        title: query["title"] || "",
        priority: validate_priority(query["priority"] || ""),
        tags: parse_tags(query["tags"]),
        click: query["click"] || "",
        attach: query["attach"] || "",
        filename: query["filename"] || "",
        icon: query["icon"] || "",
        email: query["email"] || "",
        delay: query["delay"] || "",
        cache: query["cache"] not in ["no", "false", "0"],
        firebase: query["firebase"] not in ["no", "false", "0"]
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    title = Map.get(params, :title, config.title)
    click = Map.get(params, :click, config.click)
    config = %{config | title: title, click: click}

    url = build_url(config)
    headers = build_headers(config)

    opts =
      if config.username != "" do
        [body: message, headers: headers, auth: {:basic, "#{config.username}:#{config.password}"}]
      else
        [body: message, headers: headers]
      end

    case Holler.HTTP.post(url, opts) do
      {:ok, %{status: status}} when status in 200..299 ->
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

  defp parse_topic(%URI{path: nil}), do: {:error, :missing_topic}
  defp parse_topic(%URI{path: ""}), do: {:error, :missing_topic}
  defp parse_topic(%URI{path: "/"}), do: {:error, :missing_topic}

  defp parse_topic(%URI{path: path}) do
    topic = String.trim_leading(path, "/")

    if topic == "" do
      {:error, :missing_topic}
    else
      {:ok, topic}
    end
  end

  defp parse_credentials(%URI{userinfo: nil}), do: {"", ""}
  defp parse_credentials(%URI{userinfo: ""}), do: {"", ""}

  defp parse_credentials(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [user, pass] -> {user, pass}
      [user] -> {user, ""}
    end
  end

  defp validate_priority(p) when p in @valid_priorities, do: p
  defp validate_priority(_), do: ""

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []
  defp parse_tags(tags), do: String.split(tags, ",", trim: true)

  defp build_url(config) do
    "#{config.scheme}://#{config.host}/#{config.topic}"
  end

  defp build_headers(config) do
    [
      {"content-type", "text/plain"}
    ]
    |> add_header("Title", config.title)
    |> add_header("Priority", config.priority)
    |> add_header("Tags", Enum.join(config.tags, ","))
    |> add_header("Click", config.click)
    |> add_header("Attach", config.attach)
    |> add_header("Filename", config.filename)
    |> add_header("X-Icon", config.icon)
    |> add_header("Email", config.email)
    |> add_header("Delay", config.delay)
    |> then(fn headers ->
      if config.cache, do: headers, else: [{"Cache", "no"} | headers]
    end)
    |> then(fn headers ->
      if config.firebase, do: headers, else: [{"Firebase", "no"} | headers]
    end)
  end

  defp add_header(headers, _key, ""), do: headers
  defp add_header(headers, _key, []), do: headers
  defp add_header(headers, key, value), do: [{key, value} | headers]

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
