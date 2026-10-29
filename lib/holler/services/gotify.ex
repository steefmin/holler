defmodule Holler.Services.Gotify do
  @moduledoc """
  Gotify notification service for Holler.

  ## URL format

      gotify://hostname[:port][/path]/token[?priority=5&title=Title&disabletls=yes]

  ## Examples

      gotify://example.com/AqEtoken123456
      gotify://example.com:8080/subpath/AqEtoken123456?priority=5&title=Alert
      gotify://example.com/AqEtoken123456?disabletls=yes

  ## Params

  `title` and `priority` override the URL options. `click` is sent as the
  `client::notification` extras, so a click on the notification opens it.

  ## Token requirements

  Either a legacy token:

  - Exactly 15 characters
  - Must start with `A`
  - Only alphanumeric characters and `. - _`

  Or a Gotify 3 application token: `gtfya.` followed by 43 base64url
  characters (`A-Z a-z 0-9 - _`).
  """

  @behaviour Holler.Service

  @default_title "Holler notification"
  @default_priority 0
  @token_length 15
  @token_regex ~r/^A[a-zA-Z0-9._-]{14}$/
  @app_token_prefix "gtfya."
  @app_token_key_length 43
  @app_token_key_regex ~r/^[a-zA-Z0-9_-]{43}$/

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, host} <- parse_host(uri),
         {:ok, {path, token}} <- parse_path_and_token(uri),
         :ok <- validate_token(token) do
      query_params = parse_query(uri.query)
      disable_tls = query_params["disabletls"] in ["yes", "true", "1"]
      default_port = if disable_tls, do: 80, else: 443

      config = %{
        host: host,
        port: uri.port || default_port,
        path: path,
        token: token,
        title: query_params["title"] || @default_title,
        priority: parse_integer(query_params["priority"], @default_priority),
        disable_tls: disable_tls
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    title = Map.get(params, :title, config.title)
    priority = Map.get(params, :priority, config.priority)

    url = build_url(config)

    body =
      %{
        "message" => message,
        "title" => title,
        "priority" => priority
      }
      |> put_click(Map.get(params, :click))

    case Holler.HTTP.post(url, json: body, params: [token: config.token]) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp put_click(body, url) when is_binary(url) and url != "" do
    Map.put(body, "extras", %{"client::notification" => %{"click" => %{"url" => url}}})
  end

  defp put_click(body, _url), do: body

  defp parse_host(%URI{host: nil}), do: {:error, :missing_host}
  defp parse_host(%URI{host: ""}), do: {:error, :missing_host}
  defp parse_host(%URI{host: host}), do: {:ok, host}

  defp parse_path_and_token(%URI{path: nil}), do: {:error, :missing_token}
  defp parse_path_and_token(%URI{path: ""}), do: {:error, :missing_token}

  defp parse_path_and_token(%URI{path: path}) do
    # The last path segment is the token
    segments =
      path
      |> String.split("/", trim: true)

    case segments do
      [] ->
        {:error, :missing_token}

      parts ->
        token = List.last(parts)
        # Everything except the last segment forms the sub-path
        sub_path =
          parts
          |> Enum.drop(-1)
          |> case do
            [] -> ""
            rest -> "/" <> Enum.join(rest, "/")
          end

        {:ok, {sub_path, token}}
    end
  end

  defp validate_token(@app_token_prefix <> key) when byte_size(key) == @app_token_key_length do
    if Regex.match?(@app_token_key_regex, key) do
      :ok
    else
      {:error, {:invalid_token, :invalid_characters}}
    end
  end

  defp validate_token(@app_token_prefix <> _key), do: {:error, {:invalid_token, :wrong_length}}

  defp validate_token(token) when byte_size(token) == @token_length do
    if Regex.match?(@token_regex, token) do
      :ok
    else
      {:error, {:invalid_token, :invalid_characters}}
    end
  end

  defp validate_token(_token), do: {:error, {:invalid_token, :wrong_length}}

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)

  defp parse_integer(nil, default), do: default

  defp parse_integer(value, default) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp build_url(config) do
    scheme = if config.disable_tls, do: "http", else: "https"
    port_suffix = build_port_suffix(config)
    "#{scheme}://#{config.host}#{port_suffix}#{config.path}/message"
  end

  defp build_port_suffix(%{disable_tls: false, port: 443}), do: ""
  defp build_port_suffix(%{disable_tls: true, port: 80}), do: ""
  defp build_port_suffix(%{port: port}), do: ":#{port}"
end
