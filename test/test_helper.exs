Application.put_env(:holler, :req_options, plug: {Req.Test, Holler}, retry: false)
ExUnit.start()
