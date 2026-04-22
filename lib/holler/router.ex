defmodule Holler.Router do
  @moduledoc """
  Parses a notification URL and maps it to the appropriate service module.
  """

  @services %{
    "bark" => Holler.Services.Bark,
    "discord" => Holler.Services.Discord,
    "generic" => Holler.Services.Generic,
    "googlechat" => Holler.Services.GoogleChat,
    "hangouts" => Holler.Services.GoogleChat,
    "gotify" => Holler.Services.Gotify,
    "ifttt" => Holler.Services.IFTTT,
    "join" => Holler.Services.Join,
    "mattermost" => Holler.Services.Mattermost,
    "matrix" => Holler.Services.Matrix,
    "mercure" => Holler.Services.Mercure,
    "ntfy" => Holler.Services.Ntfy,
    "opsgenie" => Holler.Services.OpsGenie,
    "pushbullet" => Holler.Services.Pushbullet,
    "pushover" => Holler.Services.Pushover,
    "rocketchat" => Holler.Services.Rocketchat,
    "slack" => Holler.Services.Slack,
    "teams" => Holler.Services.Teams,
    "telegram" => Holler.Services.Telegram,
    "zulip" => Holler.Services.Zulip
  }

  @doc """
  Parses a URL string and returns `{:ok, {module, config}}`,
  or `{:error, reason}` for an unknown scheme or initialisation failure.
  """
  @spec locate(String.t()) :: {:ok, {module(), map()}} | {:error, term()}
  def locate(url) when is_binary(url) do
    uri = URI.parse(url)

    case Map.fetch(@services, uri.scheme) do
      {:ok, module} ->
        case module.initialize(uri) do
          {:ok, config} -> {:ok, {module, config}}
          {:error, _} = err -> err
        end

      :error ->
        {:error, {:unknown_scheme, uri.scheme}}
    end
  end

  @doc """
  Parses a URL and sends a message in one step.
  """
  @spec route(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def route(url, message, params \\ %{}) do
    case locate(url) do
      {:ok, {module, config}} -> module.send(config, message, params)
      {:error, _} = err -> err
    end
  end
end
