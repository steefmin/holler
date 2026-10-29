defmodule Holler.ClickTest do
  use ExUnit.Case, async: true

  @click "https://example.org/c/1"

  # {service, url, where the message text sits in the request}
  @last_line [
    {"discord", "discord://TOKEN@1234567890", {:json, ["content"]}},
    {"generic (raw)", "generic://example.com/webhook?contenttype=text/plain", :raw},
    {"generic (json)", "generic://example.com/webhook?template=json", {:json, ["message"]}},
    {"googlechat", "googlechat://chat.googleapis.com/v1/spaces/AAAA/messages?key=a&token=b",
     {:json, ["text"]}},
    {"ifttt", "ifttt://webhookkey/?events=notify", {:json, ["value2"]}},
    {"join", "join://shoutrrr:apikey@join/?devices=device1", {:query, "text"}},
    {"matrix", "matrix://:accesstoken@matrix.example.com/?rooms=!abc123:example.com",
     {:json, ["body"]}},
    {"mattermost", "mattermost://example.com/webhooktoken", {:json, ["text"]}},
    {"mercure", "mercure://:jwt@example.com?topic=https://example.com/books/1", {:form, "data"}},
    {"opsgenie", "opsgenie://api.opsgenie.com/apikey?title=Alert", {:json, ["description"]}},
    {"pushbullet", "pushbullet://apitoken", {:json, ["body"]}},
    {"pushover", "pushover://shoutrrr:token@userkey/", {:json, ["message"]}},
    {"rocketchat", "rocketchat://example.com/tokenA/tokenB/general", {:json, ["text"]}},
    {"slack", "slack://hook:TAAAAAAAA-BAAAAAAAA-AAAAAAAAAAAAAAAAAAAAAAAA@webhook", :slack},
    {"teams", "teams://group@tenant/altId/groupOwner?host=org.webhook.office.com",
     {:json, ["text"]}},
    {"telegram", "telegram://123456789:AABBccdd@telegram?chats=-100123456789", {:json, ["text"]}},
    {"zulip", "zulip://bot%40example.com:apikey@org.zulipchat.com/?stream=general",
     {:form, "content"}}
  ]

  for {service, url, extract} <- @last_line do
    describe "#{service}" do
      test "puts the click URL on the last line of the message" do
        [request] = send_and_capture(unquote(url), %{click: @click})
        assert extract(request, unquote(extract)) == "Hello\n" <> @click
      end

      test "leaves the message alone without a click URL" do
        [request] = send_and_capture(unquote(url), %{})
        assert extract(request, unquote(extract)) == "Hello"
      end
    end
  end

  describe "ntfy" do
    test "sends the click URL as the Click header" do
      [request] = send_and_capture("ntfy://ntfy.sh/my-topic", %{click: @click})
      assert {"click", @click} in request.headers
      assert request.body == "Hello"
    end

    test "a click URL per message overrides the one in the URL" do
      [request] =
        send_and_capture("ntfy://ntfy.sh/my-topic?click=https://example.org/old", %{click: @click})

      assert {"click", @click} in request.headers
    end
  end

  describe "gotify" do
    test "sends the click URL in the client::notification extras" do
      [request] = send_and_capture("gotify://example.com/AqEtoken1234567", %{click: @click})

      assert json(request, ["extras", "client::notification", "click", "url"]) == @click
      assert json(request, ["message"]) == "Hello"
    end

    test "sends no extras without a click URL" do
      [request] = send_and_capture("gotify://example.com/AqEtoken1234567", %{})
      refute Map.has_key?(Jason.decode!(request.body), "extras")
    end
  end

  describe "bark" do
    test "sends the click URL as url" do
      [request] = send_and_capture("bark://:devicekey@api.day.app", %{click: @click})

      assert json(request, ["url"]) == @click
      assert json(request, ["body"]) == "Hello"
    end

    test "a click URL per message overrides the one in the URL" do
      [request] =
        send_and_capture("bark://:devicekey@api.day.app?url=https://example.org/old", %{
          click: @click
        })

      assert json(request, ["url"]) == @click
    end
  end

  describe "Holler.Click.append/2" do
    test "an empty message becomes just the URL" do
      assert Holler.Click.append("", %{click: @click}) == @click
    end

    test "an empty click URL changes nothing" do
      assert Holler.Click.append("Hello", %{click: ""}) == "Hello"
    end
  end

  defp send_and_capture(url, params) do
    test_pid = self()

    Req.Test.stub(Holler, fn conn ->
      send(test_pid, {:request, %{conn | body_params: Req.Test.raw_body(conn)}})
      respond(conn)
    end)

    assert :ok = Holler.send(url, "Hello", params)
    collect()
  end

  defp collect do
    receive do
      {:request, conn} ->
        [
          %{headers: conn.req_headers, query: conn.query_string, body: conn.body_params}
          | collect()
        ]
    after
      0 -> []
    end
  end

  # Each service checks the response in its own way; this satisfies all of them.
  defp respond(conn) do
    cond do
      String.starts_with?(conn.request_path, "/api/webhooks/") ->
        Plug.Conn.send_resp(conn, 204, "")

      String.starts_with?(conn.request_path, "/services/") ->
        Plug.Conn.send_resp(conn, 200, "ok")

      true ->
        Req.Test.json(conn, %{
          "ok" => true,
          "success" => true,
          "status" => 1,
          "result" => "success"
        })
    end
  end

  defp extract(request, :raw), do: request.body
  defp extract(request, {:json, path}), do: json(request, path)
  defp extract(request, {:form, key}), do: URI.decode_query(request.body)[key]
  defp extract(request, {:query, key}), do: URI.decode_query(request.query)[key]

  # Slack sends every line of the message as its own attachment.
  defp extract(request, :slack) do
    request |> json(["attachments"]) |> Enum.map_join("\n", & &1["text"])
  end

  defp json(request, path), do: get_in(Jason.decode!(request.body), path)
end
