defmodule Holler.Services.Matrix do
  @moduledoc """
  Matrix notification service for Holler.

  Sends messages to Matrix rooms via the Matrix Client-Server API.

  Authentication supports two modes:
  - **Password login**: `matrix://user:password@host/`
  - **Access token**: `matrix://:token@host/` (empty username)

  ## URL format

      matrix://[USER:]PASSWORD@HOST[:PORT]/[?rooms=ROOM1[,ROOM2]][&disableTLS=yes]

  ## Options (query parameters)

  | Key          | Default    | Description |
  |--------------|------------|-------------|
  | `rooms`      | _(all joined rooms)_ | Comma-separated room IDs (`!id`) or aliases |
  | `disableTLS` | `no`       | Use HTTP instead of HTTPS |

  Note: Matrix has no native `title` field; include the title in the message text itself.

  ## Examples

      matrix://:myaccesstoken@matrix.example.com/?rooms=!abc123:example.com
      matrix://myuser:mypassword@matrix.example.com/?rooms=myroom:example.com&disableTLS=yes
  """

  @behaviour Holler.Service

  @impl true
  def initialize(%URI{} = uri) do
    with {:ok, host} <- parse_host(uri),
         {:ok, {username, password}} <- parse_credentials(uri) do
      query = parse_query(uri.query)
      disable_tls = query["disableTLS"] in ["yes", "true", "1"]

      rooms =
        case query["rooms"] || query["room"] do
          nil -> []
          "" -> []
          r -> String.split(r, ",", trim: true) |> Enum.map(&String.trim/1)
        end

      config = %{
        host: host,
        port: uri.port,
        username: username,
        password: password,
        rooms: rooms,
        disable_tls: disable_tls
      }

      {:ok, config}
    end
  end

  @impl true
  def send(config, message, params) do
    message = Holler.Click.append(message, params)

    rooms_override = Map.get(params, :rooms, nil)

    scheme = if config.disable_tls, do: "http", else: "https"
    port_part = if config.port, do: ":#{config.port}", else: ""
    base_url = "#{scheme}://#{config.host}#{port_part}"

    with {:ok, token} <- get_token(base_url, config.username, config.password),
         {:ok, rooms} <- resolve_rooms(base_url, token, config.rooms, rooms_override) do
      results =
        Enum.map(rooms, fn room_id ->
          send_to_room(base_url, token, room_id, message)
        end)

      case Enum.find(results, &match?({:error, _}, &1)) do
        nil -> :ok
        err -> err
      end
    end
  end

  # --- Private helpers ---

  defp parse_host(%URI{host: nil}), do: {:error, :missing_host}
  defp parse_host(%URI{host: ""}), do: {:error, :missing_host}
  defp parse_host(%URI{host: host}), do: {:ok, host}

  defp parse_credentials(%URI{userinfo: nil}), do: {:error, :missing_password}
  defp parse_credentials(%URI{userinfo: ""}), do: {:error, :missing_password}

  defp parse_credentials(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      ["", ""] -> {:error, :missing_password}
      ["", password] -> {:ok, {"", password}}
      [username, password] -> {:ok, {username, password}}
      [_] -> {:error, :missing_password}
    end
  end

  defp get_token(_base_url, "", token) do
    # Token auth: no username means the password IS the access token
    {:ok, token}
  end

  defp get_token(base_url, username, password) do
    url = "#{base_url}/_matrix/client/r0/login"

    payload = %{
      "type" => "m.login.password",
      "user" => username,
      "password" => password
    }

    case Holler.HTTP.post(url, json: payload) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %{status: status, body: body}} ->
        {:error, {:login_failed, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp resolve_rooms(base_url, token, config_rooms, nil),
    do: resolve_rooms(base_url, token, config_rooms, [])

  defp resolve_rooms(base_url, token, config_rooms, override_rooms) do
    rooms =
      if override_rooms != [] and override_rooms != nil, do: override_rooms, else: config_rooms

    if rooms == [] do
      get_joined_rooms(base_url, token)
    else
      resolve_room_ids(base_url, token, rooms)
    end
  end

  defp get_joined_rooms(base_url, token) do
    url = "#{base_url}/_matrix/client/r0/joined_rooms"

    case Holler.HTTP.get(url, headers: [{"authorization", "Bearer #{token}"}]) do
      {:ok, %{status: 200, body: %{"joined_rooms" => rooms}}} ->
        {:ok, rooms}

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp resolve_room_ids(base_url, token, rooms) do
    resolved =
      Enum.map(rooms, fn room ->
        if String.starts_with?(room, "!") do
          room
        else
          alias_str = if String.starts_with?(room, "#"), do: room, else: "##{room}"
          resolve_alias(base_url, token, alias_str)
        end
      end)

    errors = Enum.filter(resolved, &match?({:error, _}, &1))

    if errors == [] do
      {:ok, resolved}
    else
      List.first(errors)
    end
  end

  defp resolve_alias(base_url, token, room_alias) do
    encoded = URI.encode(room_alias)
    url = "#{base_url}/_matrix/client/r0/directory/room/#{encoded}"

    case Holler.HTTP.get(url, headers: [{"authorization", "Bearer #{token}"}]) do
      {:ok, %{status: 200, body: %{"room_id" => room_id}}} ->
        room_id

      {:ok, %{status: status, body: body}} ->
        {:error, {:alias_lookup_failed, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp send_to_room(base_url, token, room_id, message) do
    txn_id = :erlang.unique_integer([:positive])
    encoded_room = URI.encode(room_id)
    url = "#{base_url}/_matrix/client/r0/rooms/#{encoded_room}/send/m.room.message/#{txn_id}"

    payload = %{
      "msgtype" => "m.text",
      "body" => message
    }

    case Holler.HTTP.put(url, json: payload, headers: [{"authorization", "Bearer #{token}"}]) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_query(nil), do: %{}
  defp parse_query(query), do: URI.decode_query(query)
end
