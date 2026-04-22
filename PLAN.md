# Holler — Implementatieplan

Elixir-port van [shoutrrr](https://github.com/containrrr/shoutrrr): een notificatiebibliotheek
met URL-gebaseerde configuratie. Eerste scope: Gotify. Daarna uitbreidbaar naar andere services.

---

## Architectuuroverzicht

```
Holler.send("gotify://host/token?title=Test", "Hallo!")
    │
    ▼
Holler                        # publieke API
    │
    ▼
Holler.Router                 # parst URL-scheme → kiest service-module
    │
    ▼
Holler.Service (behaviour)    # @callback initialize/1, send/3
    │
    ▼
Holler.Services.Gotify        # concrete implementatie
    │
    ▼
Req.post(...)                 # HTTP naar Gotify server
```

---

## Fase 1 — Fundament

### 1.1 `Holler.Service` behaviour (`lib/holler/service.ex`)

Definieert de interface die elke service moet implementeren:

```elixir
@callback initialize(URI.t()) :: {:ok, config :: map} | {:error, term}
@callback send(config :: map, message :: String.t(), params :: map) :: :ok | {:error, term}
```

Optioneel: een `validate_url/1` callback voor URL-validatie bij compile-time.

### 1.2 `Holler.Router` (`lib/holler/router.ex`)

Verantwoordelijk voor:
- URL parsen met `URI.parse/1`
- Scheme mappen naar een service-module via een statische map:
  ```elixir
  @services %{"gotify" => Holler.Services.Gotify}
  ```
- `locate/1` → geeft `{module, config}` terug
- `route/2` → parst URL en stuurt bericht in één stap

### 1.3 `Holler.Sender` struct (`lib/holler/sender.ex`)

Houdt een lijst van `{module, config}` tuples bij voor hergebruik:

```elixir
%Holler.Sender{services: [{Holler.Services.Gotify, %{...}}, ...]}
```

- `new/1` → accepteert lijst van URL-strings, initialiseert alle services
- `send/2` → stuurt naar alle services via `Task.async_stream` (concurrent, met timeout)
- Geeft lijst van resultaten terug: `[:ok | {:error, term}]`

### 1.4 `Holler` publieke API (`lib/holler.ex`)

```elixir
# Enkelvoudig sturen via één URL
Holler.send("gotify://hostname/AqEtoken123456", "Bericht")

# Sender aanmaken voor meerdere URLs (herbruikbaar)
{:ok, sender} = Holler.create_sender(["gotify://host1/token1", "gotify://host2/token2"])
Holler.Sender.send(sender, "Bericht")
```

---

## Fase 2 — Gotify service

### `Holler.Services.Gotify` (`lib/holler/services/gotify.ex`)

#### URL-formaat (overgenomen uit shoutrrr)
```
gotify://hostname[:port][/path]/token[?priority=5&title=Titel&disabletls=yes]
```

Voorbeelden:
```
gotify://example.com/AqEtoken123456
gotify://example.com:8080/subpath/AqEtoken123456?priority=5&title=Alert
gotify://example.com/AqEtoken123456?disabletls=yes
```

#### Config struct (plain map of struct)
```elixir
%{
  host:        "example.com",       # verplicht
  port:        443,                  # optioneel, default 443 (of 80 bij disabletls)
  path:        "",                   # optioneel subpath
  token:       "AqEtoken123456",    # verplicht, 15 tekens, begint met 'A'
  title:       "Holler notification", # default
  priority:    0,                    # default
  disable_tls: false                 # default
}
```

#### Token-validatie (overgenomen uit shoutrrr)
- Exact 15 tekens
- Begint met `'A'`
- Alleen: `a-z A-Z 0-9 . - _`

#### HTTP-aanroep
```
POST https://hostname[:port][/path]/message?token=TOKEN
Content-Type: application/json

{"message": "...", "title": "...", "priority": 0}
```

Succesvolle response: HTTP 200 met JSON-body (message object).
Foutstatus: HTTP 4xx/5xx → `{:error, reason}`.

#### Implementatie
```elixir
defmodule Holler.Services.Gotify do
  @behaviour Holler.Service

  @impl true
  def initialize(%URI{} = uri) do
    # parseer host, path, token, query params
    # valideer token
    # geef {:ok, config} of {:error, reason}
  end

  @impl true
  def send(config, message, params) do
    # merge params in config (title/priority overschrijven)
    # bouw POST-URL
    # stuur via Req.post/2
    # interpreteer response
  end
end
```

---

## Fase 3 — Extra services (later)

Volgorde op basis van populariteit en eenvoud van API:

| Service     | URL-scheme    | API-type        | Status       |
|-------------|---------------|-----------------|--------------|
| Gotify      | `gotify`      | REST/HTTP       | ✓ klaar      |
| Slack       | `slack`       | Webhook (JSON)  | ✓ klaar      |
| Generic     | `generic`     | HTTP webhook    | ✓ klaar      |
| Discord     | `discord`     | Webhook (JSON)  | ✓ klaar      |
| Telegram    | `telegram`    | Bot API (REST)  | ✓ klaar      |
| Ntfy        | `ntfy`        | REST/HTTP       | ✓ klaar      |
| Teams       | `teams`       | Webhook (JSON)  | ✓ klaar      |
| Pushover    | `pushover`    | REST            | ✓ klaar      |
| Bark        | `bark`        | REST/HTTP       | ✓ klaar      |
| Google Chat | `googlechat`  | Webhook (JSON)  | ✓ klaar      |
| IFTTT       | `ifttt`       | Webhook (JSON)  | ✓ klaar      |
| Join        | `join`        | REST            | ✓ klaar      |
| Mattermost  | `mattermost`  | Webhook (JSON)  | ✓ klaar      |
| Matrix      | `matrix`      | Client API REST | ✓ klaar      |
| OpsGenie    | `opsgenie`    | REST            | ✓ klaar      |
| Pushbullet  | `pushbullet`  | REST            | ✓ klaar      |
| Rocketchat  | `rocketchat`  | Webhook (JSON)  | ✓ klaar      |
| Zulip       | `zulip`       | Bot API (REST)  | ✓ klaar      |
| Mercure     | `mercure`     | HTTP POST/SSE   | ✓ klaar      |
| SMTP        | `smtp`        | SMTP-protocol   | out of scope |

Elke nieuwe service volgt hetzelfde patroon: één module, `initialize/1` + `send/3`,
registratie in `Holler.Router.@services`.

---

## Fase 4 — Kwaliteit & publicatie

- [ ] Volledige ExDoc documentatie (moduledoc + typespecs)
- [ ] Mix task: `mix holler.send <url> <message>`
- [ ] Hex.pm publicatie (`mix hex.publish`)
- [ ] GitHub Actions CI (mix test + mix dialyzer)
- [ ] Dialyzer typespecs doorheen de codebase

---

## Bestandsoverzicht (huidige situatie)

```
lib/
├── holler.ex                        # send/2, create_sender/1
└── holler/
    ├── service.ex                   # @behaviour
    ├── router.ex                    # URL → module + config
    ├── sender.ex                    # multi-service sender
    └── services/
        ├── bark.ex
        ├── discord.ex
        ├── generic.ex
        ├── google_chat.ex
        ├── gotify.ex
        ├── ifttt.ex
        ├── join.ex
        ├── matrix.ex
        ├── mattermost.ex
        ├── ntfy.ex
        ├── opsgenie.ex
        ├── pushbullet.ex
        ├── pushover.ex
        ├── rocketchat.ex
        ├── slack.ex
        ├── teams.ex
        ├── telegram.ex
        └── zulip.ex

test/
├── holler_test.exs                  # publieke API tests
└── services/
    ├── gotify_test.exs
    ├── slack_test.exs
    └── generic_test.exs
```

---

## Beslissingen & afwijkingen van shoutrrr

| Onderwerp | Shoutrrr (Go) | Holler (Elixir) |
|-----------|---------------|-----------------|
| Concurrency | goroutines + channels | `Task.async_stream` |
| Config | struct met reflection/tags | plain map of typed struct |
| Error handling | meerdere return values | `{:ok, _}` / `{:error, _}` tuples |
| HTTP client | `net/http` | `Req` |
| Sender state | mutable struct pointer | immutable struct, doorgeven als argument |
| Logger | `StdLogger` interface | optioneel `:logger` via Elixir `Logger` |
