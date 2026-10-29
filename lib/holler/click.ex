defmodule Holler.Click do
  @moduledoc false

  # For services without a click field of their own: the URL from
  # `params.click` becomes the last line of the message.

  def append(message, %{click: url}) when is_binary(url) and url != "" do
    if message == "", do: url, else: message <> "\n" <> url
  end

  def append(message, _params), do: message
end
