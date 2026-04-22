defmodule Holler.Services.OpsGenie do
  @moduledoc """
  OpsGenie notification service for Holler.

  Creates alerts via the OpsGenie Alert API.

  ## URL format

      opsgenie://[HOST[:PORT]/]APIKEY[?options]

  ## Options (query parameters)

  | Key           | Default              | Description |
  |---------------|----------------------|-------------|
  | `alias`       | _(none)_             | Client-defined identifier |
  | `description` | _(none)_             | Description of the alert |
  | `responders`  | _(none)_             | JSON array of responder objects |
  | `visibleTo`   | _(none)_             | JSON array of visibility objects |
  | `actions`     | _(none)_             | Custom action names (comma-separated) |
  | `tags`        | _(none)_             | Alert tags (comma-separated) |
  | `details`     | _(none)_             | JSON object of key-value pairs |
  | `entity`      | _(none)_             | Entity field |
  | `source`      | _(none)_             | Source field |
  | `priority`    | _(none)_             | `P1`–`P5` |
  | `user`        | _(none)_             | Display name of the request owner |
  | `note`        | _(none)_             | Additional note |
  | `title`       | _(none)_             | Alert message (used as OpsGenie `message` field) |

  ## Example

      opsgenie://api.opsgenie.com/myapikey?alias=test&priority=P2&tags=infra,critical
  """

  @behaviour Holler.Service

  @default_host "api.opsgenie.com"
  @default_port 443

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, api_key} <- parse_api_key(uri) do
      query = parse_query(uri.query)

      host = uri.host || @default_host
      port = uri.port || @default_port

      config = %{
        host: host,
        port: port,
        api_key: api_key,
        alias: query["alias"] || "",
        description: query["description"] || "",
        responders: query["responders"] || "",
        visible_to: query["visibleTo"] || "",
        actions: query["actions"] || "",
        tags: query["tags"] || "",
        details: query["details"] || "",
        entity: query["entity"] || "",
        source: query["source"] || "",
        priority: query["priority"] || "",
        user: query["user"] || "",
        note: query["note"] || "",
        title: query["title"] || ""
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    title = Map.get(params, :title, config.title)

    port_suffix = if config.port == @default_port, do: "", else: ":#{config.port}"
    url = "https://#{config.host}#{port_suffix}/v2/alerts"

    # `message` is OpsGenie's required alert message (max 130 chars),
    # title (if set) takes that role; otherwise we use the message body.
    alert_message = if title != "", do: title, else: String.slice(message, 0, 130)

    payload =
      %{"message" => alert_message}
      |> put_optional("description", if(title != "", do: message, else: config.description))
      |> put_optional("alias", override(params, :alias, config.alias))
      |> put_optional(
        "responders",
        parse_json_or_csv(override(params, :responders, config.responders))
      )
      |> put_optional(
        "visibleTo",
        parse_json_or_csv(override(params, :visible_to, config.visible_to))
      )
      |> put_optional("actions", parse_csv(override(params, :actions, config.actions)))
      |> put_optional("tags", parse_csv(override(params, :tags, config.tags)))
      |> put_optional("details", parse_json_map(override(params, :details, config.details)))
      |> put_optional("entity", override(params, :entity, config.entity))
      |> put_optional("source", override(params, :source, config.source))
      |> put_optional("priority", override(params, :priority, config.priority))
      |> put_optional("user", override(params, :user, config.user))
      |> put_optional("note", override(params, :note, config.note))

    case Req.post(url,
           json: payload,
           headers: [{"authorization", "GenieKey #{config.api_key}"}]
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  # --- Private helpers ---

  defp parse_api_key(%URI{path: nil}), do: {:error, :missing_api_key}
  defp parse_api_key(%URI{path: ""}), do: {:error, :missing_api_key}

  defp parse_api_key(%URI{path: path}) do
    key = String.trim_leading(path, "/")
    if key == "", do: {:error, :missing_api_key}, else: {:ok, key}
  end

  defp override(params, key, default) do
    case Map.fetch(params, key) do
      {:ok, val} ->
        val

      :error ->
        case Map.fetch(params, Atom.to_string(key)) do
          {:ok, val} -> val
          :error -> default
        end
    end
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, ""), do: map
  defp put_optional(map, _key, []), do: map
  defp put_optional(map, _key, m) when is_map(m) and map_size(m) == 0, do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp parse_csv(""), do: []
  defp parse_csv(nil), do: []
  defp parse_csv(s) when is_binary(s), do: String.split(s, ",", trim: true)
  defp parse_csv(v), do: v

  defp parse_json_or_csv(""), do: []
  defp parse_json_or_csv(nil), do: []

  defp parse_json_or_csv(s) when is_binary(s) do
    case Jason.decode(s) do
      {:ok, decoded} -> decoded
      _ -> String.split(s, ",", trim: true)
    end
  end

  defp parse_json_or_csv(v), do: v

  defp parse_json_map(""), do: %{}
  defp parse_json_map(nil), do: %{}

  defp parse_json_map(s) when is_binary(s) do
    case Jason.decode(s) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp parse_json_map(v), do: v

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
