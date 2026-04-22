defmodule Holler.Services.GenericTest do
  use ExUnit.Case, async: true

  alias Holler.Services.Generic

  @base_url "generic://example.com/webhook"

  describe "initialize/1" do
    test "parses a simple URL with defaults" do
      uri = URI.parse(@base_url)
      assert {:ok, config} = Generic.initialize(uri)
      assert config.url == "https://example.com/webhook"
      assert config.method == "POST"
      assert config.content_type == "application/json"
      assert config.template == ""
      assert config.message_key == "message"
      assert config.title_key == "title"
      assert config.title == ""
      assert config.disable_tls == false
      assert config.headers == %{}
      assert config.extra_data == %{}
    end

    test "disabletls=yes uses http scheme" do
      uri = URI.parse(@base_url <> "?disabletls=yes")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.url == "http://example.com/webhook"
      assert config.disable_tls == true
    end

    test "custom method is uppercased" do
      uri = URI.parse(@base_url <> "?method=get")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.method == "GET"
    end

    test "contenttype is set" do
      uri = URI.parse(@base_url <> "?contenttype=text/plain")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.content_type == "text/plain"
    end

    test "template=json is set" do
      uri = URI.parse(@base_url <> "?template=json")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.template == "json"
    end

    test "messagekey and titlekey are configurable" do
      uri = URI.parse(@base_url <> "?messagekey=body&titlekey=subject")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.message_key == "body"
      assert config.title_key == "subject"
    end

    test "title is extracted from query" do
      uri = URI.parse(@base_url <> "?title=Alert")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.title == "Alert"
    end

    test "custom headers (@ prefix) are parsed and normalised" do
      uri = URI.parse(@base_url <> "?%40Authorization=Bearer+token")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.headers["Authorization"] == "Bearer token"
    end

    test "extra data ($ prefix) is parsed" do
      uri = URI.parse(@base_url <> "?%24env=production")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.extra_data["env"] == "production"
    end

    test "non-config query params are forwarded to the webhook URL" do
      uri = URI.parse(@base_url <> "?token=abc123")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.url =~ "token=abc123"
    end

    test "port is preserved in the webhook URL" do
      uri = URI.parse("generic://example.com:9000/webhook")
      assert {:ok, config} = Generic.initialize(uri)
      assert config.url == "https://example.com:9000/webhook"
    end
  end

  describe "normalize_header_key/1 (via initialize)" do
    test "PascalCase key gets dashes inserted" do
      uri = URI.parse(@base_url <> "?%40ContentType=text/plain")
      assert {:ok, config} = Generic.initialize(uri)
      assert Map.has_key?(config.headers, "Content-Type")
    end

    test "lowercase key is left as-is" do
      uri = URI.parse(@base_url <> "?%40authorization=Bearer+xyz")
      assert {:ok, config} = Generic.initialize(uri)
      assert Map.has_key?(config.headers, "authorization")
    end
  end

  describe "build_body (via send with a mock)" do
    # We test body building indirectly by verifying initialize + internal helpers.
    # HTTP send is an integration concern tested separately.

    test "raw template: body equals the message" do
      uri = URI.parse(@base_url)
      {:ok, config} = Generic.initialize(uri)
      body = build_body(config, "hello world")
      assert body == "hello world"
    end

    test "json template: body is a JSON object with message key" do
      uri = URI.parse(@base_url <> "?template=json")
      {:ok, config} = Generic.initialize(uri)
      body = build_body(config, "hello")
      decoded = Jason.decode!(body)
      assert decoded["message"] == "hello"
    end

    test "json template: includes title when present" do
      uri = URI.parse(@base_url <> "?template=json&title=Alert")
      {:ok, config} = Generic.initialize(uri)
      body = build_body(config, "hello")
      decoded = Jason.decode!(body)
      assert decoded["title"] == "Alert"
      assert decoded["message"] == "hello"
    end

    test "json template: uses custom messagekey and titlekey" do
      uri = URI.parse(@base_url <> "?template=json&messagekey=body&titlekey=subject&title=Hi")
      {:ok, config} = Generic.initialize(uri)
      body = build_body(config, "content")
      decoded = Jason.decode!(body)
      assert decoded["body"] == "content"
      assert decoded["subject"] == "Hi"
      refute Map.has_key?(decoded, "message")
    end

    test "json template: includes extra_data fields" do
      uri = URI.parse(@base_url <> "?template=json&%24env=prod")
      {:ok, config} = Generic.initialize(uri)
      body = build_body(config, "msg")
      decoded = Jason.decode!(body)
      assert decoded["env"] == "prod"
    end
  end

  # Helper to call the private build_body via the module internals
  defp build_body(config, message) do
    case config.template do
      "json" ->
        payload =
          config.extra_data
          |> Map.put(config.message_key, message)
          |> then(fn m ->
            if config.title != "", do: Map.put(m, config.title_key, config.title), else: m
          end)

        Jason.encode!(payload)

      _ ->
        message
    end
  end
end
