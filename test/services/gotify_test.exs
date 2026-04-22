defmodule Holler.Services.GotifyTest do
  use ExUnit.Case, async: true

  alias Holler.Services.Gotify

  describe "initialize/1" do
    test "parses a simple URL correctly" do
      uri = URI.parse("gotify://example.com/AqEtoken1234567")
      assert {:ok, config} = Gotify.initialize(uri)
      assert config.host == "example.com"
      assert config.token == "AqEtoken1234567"
      assert config.port == 443
      assert config.path == ""
      assert config.title == "Holler notification"
      assert config.priority == 0
      assert config.disable_tls == false
    end

    test "parses URL with port and sub-path" do
      uri = URI.parse("gotify://example.com:8080/subpath/AqEtoken1234567")
      assert {:ok, config} = Gotify.initialize(uri)
      assert config.port == 8080
      assert config.path == "/subpath"
      assert config.token == "AqEtoken1234567"
    end

    test "parses query parameters" do
      uri = URI.parse("gotify://example.com/AqEtoken1234567?priority=5&title=Alert")
      assert {:ok, config} = Gotify.initialize(uri)
      assert config.priority == 5
      assert config.title == "Alert"
    end

    test "sets disable_tls and uses port 80 as default" do
      uri = URI.parse("gotify://example.com/AqEtoken1234567?disabletls=yes")
      assert {:ok, config} = Gotify.initialize(uri)
      assert config.disable_tls == true
      assert config.port == 80
    end

    test "returns error for missing host" do
      uri = %URI{scheme: "gotify", host: nil, path: "/AqEtoken123456"}
      assert {:error, :missing_host} = Gotify.initialize(uri)
    end

    test "returns error for missing token" do
      uri = URI.parse("gotify://example.com/")
      assert {:error, :missing_token} = Gotify.initialize(uri)
    end

    test "returns error for token with wrong length" do
      uri = URI.parse("gotify://example.com/Ashort")
      assert {:error, {:invalid_token, :wrong_length}} = Gotify.initialize(uri)
    end

    test "returns error for token not starting with A" do
      uri = URI.parse("gotify://example.com/BqEtoken1234567")
      assert {:error, {:invalid_token, :invalid_characters}} = Gotify.initialize(uri)
    end

    test "returns error for token with invalid characters" do
      uri = URI.parse("gotify://example.com/AqEtoken!@#$%^")
      assert {:error, {:invalid_token, _}} = Gotify.initialize(uri)
    end

    test "accepts token with valid special characters (dot, dash, underscore)" do
      uri = URI.parse("gotify://example.com/Aq.to-en_123456")
      assert {:ok, config} = Gotify.initialize(uri)
      assert config.token == "Aq.to-en_123456"
    end
  end
end
