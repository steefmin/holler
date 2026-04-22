defmodule Holler.Services.DiscordTest do
  use ExUnit.Case, async: true

  alias Holler.Services.Discord

  @token "abcdefghijklmnop"
  @webhook_id "1234567890"
  @base_url "discord://#{@token}@#{@webhook_id}"

  describe "initialize/1" do
    test "parses token and webhook_id" do
      uri = URI.parse(@base_url)
      assert {:ok, config} = Discord.initialize(uri)
      assert config.token == @token
      assert config.webhook_id == @webhook_id
    end

    test "defaults are empty strings" do
      uri = URI.parse(@base_url)
      assert {:ok, config} = Discord.initialize(uri)
      assert config.username == ""
      assert config.avatar == ""
      assert config.thread_id == ""
    end

    test "parses query params" do
      uri =
        URI.parse(
          @base_url <> "?username=Holler&avatar=https://example.com/pic.png&thread_id=999"
        )

      assert {:ok, config} = Discord.initialize(uri)
      assert config.username == "Holler"
      assert config.avatar == "https://example.com/pic.png"
      assert config.thread_id == "999"
    end

    test "returns error for missing webhook_id" do
      uri = %URI{scheme: "discord", host: nil, userinfo: @token}
      assert {:error, :missing_webhook_id} = Discord.initialize(uri)
    end

    test "returns error for missing token" do
      uri = %URI{scheme: "discord", host: @webhook_id, userinfo: nil}
      assert {:error, :missing_token} = Discord.initialize(uri)
    end
  end
end
