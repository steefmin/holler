defmodule Holler.HTTP do
  @moduledoc false

  # Every service calls Req through here, so `config :holler, :req_options`
  # reaches all requests (e.g. `plug: {Req.Test, Holler}` in tests).

  def get(url, opts), do: Req.get(url, merge(opts))
  def post(url, opts), do: Req.post(url, merge(opts))
  def put(url, opts), do: Req.put(url, merge(opts))
  def request(opts), do: Req.request(merge(opts))

  defp merge(opts), do: Keyword.merge(opts, Application.get_env(:holler, :req_options, []))
end
