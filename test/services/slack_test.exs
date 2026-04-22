defmodule Holler.Services.SlackTest do
  use ExUnit.Case, async: true

  alias Holler.Services.Slack

  # Valid token parts that satisfy the regex:
  #   p1, p2 = 9+ uppercase alphanumeric
  #   p3     = 24+ mixed-case alphanumeric
  @p1 "TAAAAAAAA"
  @p2 "BAAAAAAAA"
  @p3 "AAAAAAAAAAAAAAAAAAAAAAAA"

  # Modern webhook: token in userinfo with '-' separators, channel = "webhook"
  @webhook_modern "slack://hook:#{@p1}-#{@p2}-#{@p3}@webhook"
  # Legacy webhook: token spread across host and path with '/' as separators
  @webhook_legacy "slack://#{@p1}/#{@p2}/#{@p3}"
  # Bot API: xoxb token in userinfo, real channel in host
  @bot_api "slack://xoxb:#{@p1}-#{@p2}-#{@p3}@CXXXXXXXXXX"

  describe "initialize/1 — webhook (modern)" do
    test "parses token parts correctly" do
      uri = URI.parse(@webhook_modern)
      assert {:ok, config} = Slack.initialize(uri)
      assert config.token.type == "hook"
      assert config.token.p1 == @p1
      assert config.token.p2 == @p2
      assert config.token.p3 == @p3
    end

    test "sets mode to :webhook" do
      uri = URI.parse(@webhook_modern)
      assert {:ok, %{mode: :webhook}} = Slack.initialize(uri)
    end

    test "sets channel to 'webhook'" do
      uri = URI.parse(@webhook_modern)
      assert {:ok, %{channel: "webhook"}} = Slack.initialize(uri)
    end
  end

  describe "initialize/1 — webhook (legacy)" do
    test "parses token from host and path" do
      uri = URI.parse(@webhook_legacy)
      assert {:ok, config} = Slack.initialize(uri)
      assert config.token.p1 == @p1
      assert config.token.p2 == @p2
      assert config.token.p3 == @p3
      assert config.mode == :webhook
      assert config.channel == "webhook"
    end
  end

  describe "initialize/1 — Bot API token" do
    test "parses xoxb token and channel" do
      uri = URI.parse(@bot_api)
      assert {:ok, config} = Slack.initialize(uri)
      assert config.token.type == "xoxb"
      assert config.token.p1 == @p1
      assert config.token.p2 == @p2
      assert config.token.p3 == @p3
      assert config.channel == "CXXXXXXXXXX"
      assert config.mode == :api
    end
  end

  describe "initialize/1 — token validation" do
    test "returns error for mismatched separators" do
      # p1/p2 use ',' but p2/p3 use '-'
      uri = URI.parse("slack://hook:#{@p1},#{@p2}-#{@p3}@webhook")
      assert {:error, :mismatched_token_separators} = Slack.initialize(uri)
    end

    test "returns error for token part too short" do
      uri = URI.parse("slack://hook:SHORT/SHORT/TOOSHORT")
      assert {:error, :invalid_token} = Slack.initialize(uri)
    end

    test "returns error for completely invalid token" do
      uri = URI.parse("slack://hook:notavalidtoken")
      assert {:error, :invalid_token} = Slack.initialize(uri)
    end

    test "returns error for legacy URL with wrong number of parts" do
      uri = URI.parse("slack://#{@p1}/#{@p2}")
      assert {:error, :invalid_token} = Slack.initialize(uri)
    end
  end

  describe "initialize/1 — query parameters" do
    test "parses bot_name, color, title, thread_ts, icon" do
      url =
        @webhook_modern <>
          "?bot_name=Holler&color=%23ff0000&title=Alert&thread_ts=12345&icon=:robot:"

      uri = URI.parse(url)
      assert {:ok, config} = Slack.initialize(uri)
      assert config.bot_name == "Holler"
      assert config.color == "#ff0000"
      assert config.title == "Alert"
      assert config.thread_ts == "12345"
      assert config.icon == ":robot:"
    end

    test "defaults to empty strings when query params are absent" do
      uri = URI.parse(@webhook_modern)
      assert {:ok, config} = Slack.initialize(uri)
      assert config.bot_name == ""
      assert config.color == ""
      assert config.title == ""
      assert config.thread_ts == ""
      assert config.icon == ""
    end
  end

  describe "build_payload/2" do
    setup do
      uri = URI.parse(@webhook_modern)
      {:ok, config} = Slack.initialize(uri)
      {:ok, config: config}
    end

    test "creates one attachment per line", %{config: config} do
      payload = Slack.build_payload(config, "line one\nline two")
      assert length(payload["attachments"]) == 2
      assert Enum.at(payload["attachments"], 0)["text"] == "line one"
      assert Enum.at(payload["attachments"], 1)["text"] == "line two"
    end

    test "single-line message produces one attachment", %{config: config} do
      payload = Slack.build_payload(config, "hello")
      assert length(payload["attachments"]) == 1
    end

    test "trailing empty line is removed", %{config: config} do
      payload = Slack.build_payload(config, "hello\n")
      assert length(payload["attachments"]) == 1
    end

    test "messages with more than 100 lines are merged into the last attachment", %{
      config: config
    } do
      lines = Enum.map_join(1..105, "\n", &"line #{&1}")
      payload = Slack.build_payload(config, lines)
      assert length(payload["attachments"]) == 100
      last = List.last(payload["attachments"])["text"]
      assert last =~ "line 101"
      assert last =~ "line 105"
    end

    test "sets title as top-level text", %{config: config} do
      config = %{config | title: "My Title"}
      payload = Slack.build_payload(config, "hello")
      assert payload["text"] == "My Title"
    end

    test "sets icon_emoji for non-URL icon", %{config: config} do
      config = %{config | icon: ":robot:"}
      payload = Slack.build_payload(config, "hello")
      assert payload["icon_emoji"] == ":robot:"
      refute Map.has_key?(payload, "icon_url")
    end

    test "sets icon_url for URL icon", %{config: config} do
      config = %{config | icon: "https://example.com/icon.png"}
      payload = Slack.build_payload(config, "hello")
      assert payload["icon_url"] == "https://example.com/icon.png"
      refute Map.has_key?(payload, "icon_emoji")
    end

    test "applies color to all attachments", %{config: config} do
      config = %{config | color: "#ff0000"}
      payload = Slack.build_payload(config, "a\nb")
      assert Enum.all?(payload["attachments"], &(&1["color"] == "#ff0000"))
    end

    test "does not include channel for webhook mode", %{config: config} do
      payload = Slack.build_payload(config, "hello")
      refute Map.has_key?(payload, "channel")
    end

    test "includes channel for API mode" do
      uri = URI.parse(@bot_api)
      {:ok, config} = Slack.initialize(uri)
      payload = Slack.build_payload(config, "hello")
      assert payload["channel"] == "CXXXXXXXXXX"
    end
  end
end
