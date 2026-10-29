defmodule Holler.Services.Teams do
  @moduledoc """
  Microsoft Teams notification service for Holler.

  Sends messages via an incoming Teams webhook (Office 365 Connector).

  ## URL format

      teams://GROUP@TENANT/ALTID/GROUPOWNER?host=ORGANIZATION.webhook.office.com

  The parts are extracted from your Teams webhook URL:

      https://ORGANIZATION.webhook.office.com/webhookb2/GROUP@TENANT/IncomingWebhook/ALTID/GROUPOWNER

  ## Options (query parameters)

  | Key     | Default                    | Description |
  |---------|----------------------------|-------------|
  | `host`  | `outlook.office.com`       | Webhook host (e.g. `myorg.webhook.office.com`) |
  | `title` | _(none)_                   | Card title |
  | `color` | _(none)_                   | Theme color (hex, e.g. `#ff0000`) |

  ## Example

      teams://abc123@def456/ghi789/jkl012?host=myorg.webhook.office.com&title=Alert
  """

  @behaviour Holler.Service

  @default_host "outlook.office.com"

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, group} <- parse_group(uri),
         {:ok, tenant} <- parse_tenant(uri),
         {:ok, {alt_id, group_owner}} <- parse_path(uri) do
      query = parse_query(uri.query)

      config = %{
        group: group,
        tenant: tenant,
        alt_id: alt_id,
        group_owner: group_owner,
        host: query["host"] || @default_host,
        title: query["title"] || "",
        color: query["color"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    message = Holler.Click.append(message, params)

    title = Map.get(params, :title, config.title)
    color = Map.get(params, :color, config.color)

    url = build_url(config)

    payload = build_payload(message, title, color)

    case Holler.HTTP.post(url, json: payload) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp parse_group(%URI{userinfo: nil}), do: {:error, :missing_group}
  defp parse_group(%URI{userinfo: ""}), do: {:error, :missing_group}
  defp parse_group(%URI{userinfo: group}), do: {:ok, group}

  defp parse_tenant(%URI{host: nil}), do: {:error, :missing_tenant}
  defp parse_tenant(%URI{host: ""}), do: {:error, :missing_tenant}
  defp parse_tenant(%URI{host: tenant}), do: {:ok, tenant}

  defp parse_path(%URI{path: nil}), do: {:error, :missing_alt_id}
  defp parse_path(%URI{path: ""}), do: {:error, :missing_alt_id}

  defp parse_path(%URI{path: path}) do
    segments = String.split(path, "/", trim: true)

    case segments do
      [alt_id, group_owner] -> {:ok, {alt_id, group_owner}}
      _ -> {:error, :invalid_path}
    end
  end

  defp build_url(config) do
    "https://#{config.host}/webhookb2/#{config.group}@#{config.tenant}/IncomingWebhook/#{config.alt_id}/#{config.group_owner}"
  end

  defp build_payload(message, title, color) do
    payload = %{
      "@type" => "MessageCard",
      "@context" => "https://schema.org/extensions",
      "text" => message
    }

    payload = if title != "", do: Map.put(payload, "title", title), else: payload
    payload = if color != "", do: Map.put(payload, "themeColor", color), else: payload
    payload
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
