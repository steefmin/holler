defmodule Holler.Services.IFTTT do
  @moduledoc """
  IFTTT (If This Then That) notification service for Holler.

  Sends events to IFTTT webhooks (Maker channel).

  ## URL format

      ifttt://WEBHOOKID/?events=EVENT1[,EVENT2]&value1=V1&value2=V2&value3=V3

  ## Options (query parameters)

  | Key                 | Default | Description |
  |---------------------|---------|-------------|
  | `events`            | _(required)_ | Comma-separated list of event names |
  | `title`             | _(none)_     | Notification title |
  | `value1`            | _(none)_     | Custom value 1 |
  | `value2`            | _(none)_     | Custom value 2 |
  | `value3`            | _(none)_     | Custom value 3 |
  | `useMessageAsValue` | `2`          | Set which value field (1–3) receives the message (0 = none) |
  | `useTitleAsValue`   | `0`          | Set which value field (1–3) receives the title (0 = none) |

  ## Example

      ifttt://myWebhookKey/?events=notify&title=Alert&useMessageAsValue=1
  """

  @behaviour Holler.Service

  @api_base "https://maker.ifttt.com/trigger"

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, webhook_id} <- parse_webhook_id(uri),
         {:ok, events} <- parse_events(uri) do
      query = parse_query(uri.query)

      config = %{
        webhook_id: webhook_id,
        events: events,
        title: query["title"] || "",
        value1: query["value1"] || "",
        value2: query["value2"] || "",
        value3: query["value3"] || "",
        use_message_as_value: parse_integer(query["useMessageAsValue"], 2),
        use_title_as_value: parse_integer(query["useTitleAsValue"], 0)
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    message = Holler.Click.append(message, params)

    title = Map.get(params, :title, config.title)

    values = %{
      "value1" => config.value1,
      "value2" => config.value2,
      "value3" => config.value3
    }

    values = apply_message(values, message, config.use_message_as_value)
    values = apply_title(values, title, config.use_title_as_value)

    results =
      Enum.map(config.events, fn event ->
        send_event(config.webhook_id, event, values)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      err -> err
    end
  end

  # --- Private helpers ---

  defp parse_webhook_id(%URI{host: nil}), do: {:error, :missing_webhook_id}
  defp parse_webhook_id(%URI{host: ""}), do: {:error, :missing_webhook_id}
  defp parse_webhook_id(%URI{host: id}), do: {:ok, id}

  defp parse_events(%URI{query: nil}), do: {:error, :missing_events}

  defp parse_events(%URI{query: query}) do
    params = URI.decode_query(query)

    case params["events"] do
      nil -> {:error, :missing_events}
      "" -> {:error, :missing_events}
      events_str -> {:ok, String.split(events_str, ",", trim: true)}
    end
  end

  defp apply_message(values, _message, 0), do: values

  defp apply_message(values, message, n) when n in 1..3,
    do: Map.put(values, "value#{n}", message)

  defp apply_message(values, _message, _), do: values

  defp apply_title(values, _title, 0), do: values

  defp apply_title(values, title, n) when n in 1..3,
    do: Map.put(values, "value#{n}", title)

  defp apply_title(values, _title, _), do: values

  defp send_event(webhook_id, event, values) do
    url = "#{@api_base}/#{URI.encode(event)}/with/key/#{webhook_id}"

    case Holler.HTTP.post(url, json: values) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_integer(nil, default), do: default

  defp parse_integer(value, default) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
