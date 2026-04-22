defmodule Holler.Services.TelegramTest do
  use ExUnit.Case, async: true

  alias Holler.Services.Telegram

  @token "123456789:AABBccddEEFFggHHiiJJkk"
  @base_url "telegram://#{@token}@telegram?chats=-100123456789"

  describe "initialize/1" do
    test "parses token and chat" do
      uri = URI.parse(@base_url)
      assert {:ok, config} = Telegram.initialize(uri)
      assert config.token == @token
      assert config.chats == ["-100123456789"]
    end

    test "parses multiple chats" do
      uri = URI.parse("telegram://#{@token}@telegram?chats=111,222,@channel")
      assert {:ok, config} = Telegram.initialize(uri)
      assert config.chats == ["111", "222", "@channel"]
    end

    test "preview and notification default to true" do
      uri = URI.parse(@base_url)
      assert {:ok, config} = Telegram.initialize(uri)
      assert config.preview == true
      assert config.notification == true
    end

    test "preview=no disables preview" do
      uri = URI.parse(@base_url <> "&preview=no")
      assert {:ok, config} = Telegram.initialize(uri)
      assert config.preview == false
    end

    test "notification=no disables notification" do
      uri = URI.parse(@base_url <> "&notification=no")
      assert {:ok, config} = Telegram.initialize(uri)
      assert config.notification == false
    end

    test "parsemode is set" do
      uri = URI.parse(@base_url <> "&parsemode=HTML")
      assert {:ok, config} = Telegram.initialize(uri)
      assert config.parse_mode == "HTML"
    end

    test "invalid parsemode falls back to None" do
      uri = URI.parse(@base_url <> "&parsemode=INVALID")
      assert {:ok, config} = Telegram.initialize(uri)
      assert config.parse_mode == "None"
    end

    test "title is parsed" do
      uri = URI.parse(@base_url <> "&title=Alert")
      assert {:ok, config} = Telegram.initialize(uri)
      assert config.title == "Alert"
    end

    test "returns error for missing token" do
      uri = %URI{scheme: "telegram", host: "telegram", userinfo: nil, query: "chats=123"}
      assert {:error, :missing_token} = Telegram.initialize(uri)
    end

    test "returns error for missing chats" do
      uri = URI.parse("telegram://#{@token}@telegram")
      assert {:error, :missing_chats} = Telegram.initialize(uri)
    end

    test "returns error for invalid token format" do
      uri = URI.parse("telegram://NOCOTON@telegram?chats=123")
      assert {:error, :invalid_token_format} = Telegram.initialize(uri)
    end
  end
end
