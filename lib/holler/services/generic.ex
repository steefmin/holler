defmodule Holler.Services.Generic do
  @moduledoc """
  Generic HTTP webhook service for Holler.

  Sends a notification to any HTTP(S) endpoint. The URL scheme `generic`
  replaces `https`; use `disabletls=yes` for plain HTTP.

  ## URL format

      generic://hostname[:port][/path][?options]

  ## Config options (query parameters)

  | Key           | Default              | Description |
  |---------------|----------------------|-------------|
  | `method`      | `POST`               | HTTP method |
  | `contenttype` | `application/json`   | `Content-Type` header |
  | `template`    | _(empty)_            | Payload template: `` (raw body) or `json` |
  | `messagekey`  | `message`            | JSON key for the message (template=json) |
  | `titlekey`    | `title`              | JSON key for the title (template=json) |
  | `title`       | _(empty)_            | Title value sent with the request |
  | `disabletls`  | `false`              | Use HTTP instead of HTTPS |

  ## Custom headers

  Prefix a query key with `@` to set a request header:

      generic://example.com/hook?@Authorization=Bearer+token

  The key is normalised to `Header-Case` (`@ContentType` → `Content-Type`).

  ## Extra JSON fields

  Prefix a query key with `$` to include extra fields in the JSON payload
  (only effective when `template=json`):

      generic://example.com/hook?template=json&$env=production

  ## Examples

      # Raw POST — body is the message string
      generic://example.com/webhook

      # JSON POST — body is {"message":"...","title":"..."}
      generic://example.com/webhook?template=json

      # Custom header + extra field
      generic://example.com/webhook?template=json&@Authorization=Bearer+abc&$source=holler

      # HTTP (no TLS)
      generic://example.com/webhook?disabletls=yes
  """

  @behaviour Holler.Service

  @config_keys ~w(method contenttype template messagekey titlekey title disabletls)

  @impl true
  def initialize(%URI{} = uri) do
    query_map = parse_query(uri.query)

    {config_params, rest} = split_query(query_map)
    {headers, extra_data, webhook_query} = classify_rest(rest)

    disable_tls = config_params["disabletls"] in ["yes", "true", "1"]
    scheme = if disable_tls, do: "http", else: "https"

    # Rebuild the webhook URL with the remaining (non-config) query params
    webhook_url =
      %URI{
        scheme: scheme,
        host: uri.host,
        port: uri.port,
        path: uri.path,
        query: encode_query(webhook_query)
      }
      |> URI.to_string()

    config = %{
      url: webhook_url,
      method: String.upcase(config_params["method"] || "POST"),
      content_type: config_params["contenttype"] || "application/json",
      template: config_params["template"] || "",
      message_key: config_params["messagekey"] || "message",
      title_key: config_params["titlekey"] || "title",
      title: config_params["title"] || "",
      disable_tls: disable_tls,
      headers: headers,
      extra_data: extra_data
    }

    {:ok, config}
  end

  @impl true
  def send(config, message, params) do
    title = Map.get(params, :title, config.title)
    config = %{config | title: title}

    body = build_body(config, message)
    headers = build_headers(config)

    case Req.request(
           method: String.downcase(config.method) |> String.to_atom(),
           url: config.url,
           body: body,
           headers: headers
         ) do
      {:ok, %{status: status}} when status < 300 ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp build_body(config, message) do
    case config.template do
      "json" ->
        payload =
          config.extra_data
          |> Map.put(config.message_key, message)
          |> then(fn m ->
            if config.title != "", do: Map.put(m, config.title_key, config.title), else: m
          end)

        Jason.encode!(payload)

      _ ->
        # Raw body — just the message string
        message
    end
  end

  defp build_headers(config) do
    base = [{"content-type", config.content_type}]

    Enum.reduce(config.headers, base, fn {key, value}, acc ->
      [{String.downcase(key), value} | acc]
    end)
  end

  # Split query map into known config keys vs. everything else
  defp split_query(query_map) do
    Enum.split_with(query_map, fn {k, _v} -> k in @config_keys end)
    |> then(fn {config, rest} ->
      {Map.new(config), Map.new(rest)}
    end)
  end

  # Classify remaining query keys:
  #   @Key  → custom request header (normalised to Header-Case)
  #   $key  → extra JSON field
  #   rest  → forwarded as webhook query params
  defp classify_rest(query_map) do
    Enum.reduce(query_map, {%{}, %{}, %{}}, fn {key, value}, {headers, extra, webhook} ->
      cond do
        String.starts_with?(key, "@") ->
          header_key = normalize_header_key(String.slice(key, 1..-1//1))
          {Map.put(headers, header_key, value), extra, webhook}

        String.starts_with?(key, "$") ->
          field_key = String.slice(key, 1..-1//1)
          {headers, Map.put(extra, field_key, value), webhook}

        true ->
          {headers, extra, Map.put(webhook, key, value)}
      end
    end)
  end

  # Convert camelCase or PascalCase key to Header-Case
  # e.g. "ContentType" → "Content-Type", "authorization" → "Authorization"
  defp normalize_header_key(key) do
    key
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.flat_map(fn {char, i} ->
      if char =~ ~r/[A-Z]/ and i > 0 and String.at(key, i - 1) != "-" do
        ["-", char]
      else
        [char]
      end
    end)
    |> Enum.join()
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)

  defp encode_query(map) when map == %{}, do: nil
  defp encode_query(map), do: URI.encode_query(map)
end
