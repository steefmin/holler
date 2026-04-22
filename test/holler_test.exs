defmodule HollerTest do
  use ExUnit.Case, async: true

  describe "send/2" do
    test "returns error for unknown scheme" do
      assert {:error, {:unknown_scheme, "unknown"}} =
               Holler.send("unknown://host/token", "test")
    end

    test "returns error for invalid Gotify token" do
      assert {:error, _} = Holler.send("gotify://example.com/kortetoken", "test")
    end
  end

  describe "create_sender/1" do
    test "creates sender with valid URLs" do
      assert {:ok, sender} = Holler.create_sender(["gotify://example.com/AqEtoken1234567"])
      assert length(sender.services) == 1
    end

    test "returns error when one URL is invalid" do
      assert {:error, {_url, _reason}} =
               Holler.create_sender([
                 "gotify://example.com/AqEtoken1234567",
                 "unknown://host/token"
               ])
    end
  end
end
