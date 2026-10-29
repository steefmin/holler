# Holler

**URL-based notification library for Elixir** — send notifications to 18 services
with a single URL string. An Elixir port of [shoutrrr](https://github.com/containrrr/shoutrrr).

## Installation

Add `holler` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:holler, "~> 0.3"}
  ]
end
```

## Usage

### Send to a single service

```elixir
Holler.send("gotify://example.com/AqEtoken123456", "Hello from Holler!")
# => :ok
```

### Send to multiple services concurrently

```elixir
urls = [
  "gotify://example.com/AqEtoken123456",
  "slack://hook:TXXXXXXXX/BXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX",
  "telegram://123456789:AABBccdd@telegram?chats=-100123456789"
]

{:ok, sender} = Holler.create_sender(urls)
Holler.Sender.send(sender, "Deploy complete!")
# => [:ok, :ok, :ok]
```

### Override per-send params

```elixir
Holler.send(
  "ntfy://ntfy.sh/my-topic",
  "Disk usage at 95%",
  %{title: "Warning", priority: "high"}
)
```

### Click URL per message

Pass `click` to open a URL when the notification is tapped or clicked:

```elixir
Holler.send(
  "gotify://example.com/AqEtoken123456",
  "Your morning overview is ready",
  %{title: "Agents", click: "https://example.com/conversations/42"}
)
```

ntfy sends it as the `Click` header, Gotify as the `client::notification` extras
and Bark as `url`. Every other service gets the URL as the last line of the message.

## Supported services

| Service      | URL scheme      | Example URL |
|--------------|-----------------|-------------|
| Bark         | `bark`          | `bark://:devicekey@api.day.app` |
| Discord      | `discord`       | `discord://token@webhook_id` |
| Generic      | `generic`       | `generic://example.com/webhook` |
| Google Chat  | `googlechat`    | `googlechat://chat.googleapis.com/v1/spaces/FOO/messages?key=bar&token=baz` |
| Gotify       | `gotify`        | `gotify://example.com/AqEtoken123456` |
| IFTTT        | `ifttt`         | `ifttt://webhookkey/?events=myevent` |
| Join         | `join`          | `join://shoutrrr:apikey@join/?devices=device1` |
| Matrix       | `matrix`        | `matrix://:accesstoken@matrix.example.com/` |
| Mattermost   | `mattermost`    | `mattermost://example.com/webhooktoken` |
| Ntfy         | `ntfy`          | `ntfy://ntfy.sh/my-topic` |
| OpsGenie     | `opsgenie`      | `opsgenie://api.opsgenie.com/myapikey` |
| Pushbullet   | `pushbullet`    | `pushbullet://myapitoken` |
| Pushover     | `pushover`      | `pushover://shoutrrr:token@userkey/` |
| Rocket.Chat  | `rocketchat`    | `rocketchat://example.com/tokenA/tokenB/general` |
| Slack        | `slack`         | `slack://hook:TXXXXXXXX/BXXXXXXXX/XXXXXXXXXXXXXXXXXXXXXXXX` |
| Teams        | `teams`         | `teams://group@tenant/altId/groupOwner?host=org.webhook.office.com` |
| Telegram     | `telegram`      | `telegram://botid:token@telegram?chats=@mychannel` |
| Zulip        | `zulip`         | `zulip://bot%40example.com:apikey@org.zulipchat.com/?stream=general` |
| Mercure      | `mercure`       | `mercure://:jwt@example.com?topic=https://example.com/books/1` |

## API

### `Holler.send/3`

```elixir
@spec send(url :: String.t(), message :: String.t(), params :: map()) ::
  :ok | {:error, term()}
```

Parses `url`, initialises the matching service, and sends `message` in one step.
`params` is merged into the config and can override per-call options like `title`,
`priority` or `click`.

### `Holler.create_sender/1`

```elixir
@spec create_sender([String.t()]) :: {:ok, Holler.Sender.t()} | {:error, term()}
```

Parses and initialises all URLs upfront. Returns a `Holler.Sender` struct that can
be reused to send to all configured services concurrently.

### `Holler.Sender.send/2`

```elixir
@spec send(Holler.Sender.t(), message :: String.t(), params :: map()) ::
  [:ok | {:error, term()}]
```

Sends `message` to all services in the sender concurrently using
`Task.async_stream`. Returns a list of results in the same order as the URLs
passed to `create_sender/1`.

## License

MIT — see [LICENSE](LICENSE).
