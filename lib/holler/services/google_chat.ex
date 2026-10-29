defmodule Holler.Services.GoogleChat do
  @moduledoc """
  Google Chat notification service for Holler.

  Sends messages via a Google Chat incoming webhook.

  ## URL format

  Take your Google Chat webhook URL:

      https://chat.googleapis.com/v1/spaces/FOO/messages?key=bar&token=baz

  Replace `https` with `googlechat` (or the deprecated `hangouts`):

      googlechat://chat.googleapis.com/v1/spaces/FOO/messages?key=bar&token=baz

  ## Example

      googlechat://chat.googleapis.com/v1/spaces/AAAABBBB/messages?key=abc&token=xyz
  """

  @behaviour Holler.Service

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, host} <- parse_host(uri),
         {:ok, path} <- parse_path(uri),
         {:ok, query_string} <- parse_query_string(uri) do
      config = %{
        host: host,
        path: path,
        query_string: query_string
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    message = Holler.Click.append(message, params)

    url = "https://#{config.host}#{config.path}?#{config.query_string}"
    payload = %{"text" => message}

    case Holler.HTTP.post(url, json: payload) do
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

  defp parse_path(%URI{path: nil}), do: {:error, :missing_path}
  defp parse_path(%URI{path: ""}), do: {:error, :missing_path}
  defp parse_path(%URI{path: path}), do: {:ok, path}

  defp parse_query_string(%URI{query: nil}), do: {:error, :missing_query}
  defp parse_query_string(%URI{query: ""}), do: {:error, :missing_query}
  defp parse_query_string(%URI{query: q}), do: {:ok, q}
end
