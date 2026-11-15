# Notifications

```sh
helpoupou notify setup     # wizard: pick a service, enter its settings, test
helpoupou notify list      # channels, secrets masked
helpoupou notify test      # send a test to every channel (or: test NAME)
helpoupou notify send --level warning --title "Backup late" --body "Last one: 30 h ago"
helpoupou notify remove NAME
```

The wizard sends a test message and saves the channel only if it went through.

## How it works

- You can have **several channels**. Each has a **minimum level**: `info`,
  `warning` or `critical`. Example: everything to ntfy, only `critical` to
  Telegram.
- One channel failing never blocks the others.
- One retry per message: after the delay asked by the service on a rate limit,
  after 2 seconds on a network or server error.
- Secrets are stored in `~/.config/helpoupou/notify.conf` (mode 600) and are
  passed to `curl` through its standard input, never on the command line.
- `helpoupou doctor` on a server warns when no channel exists or when the last
  delivery of a channel failed.

A project can have its own channels in `.helpoupou/notify.conf` (use
`notify setup --project`). When that file exists it replaces the machine
channels for this project. Keep it out of git: `helpoupou init` adds it to
`.gitignore`.

## Without a terminal

```sh
HELPOUPOU_NOTIFY_URL=... helpoupou --yes notify setup --provider discord --name ops
```

Each setting is read from `HELPOUPOU_NOTIFY_<SETTING>` (upper case).

## Providers

| Provider | Settings | Where to get them |
|---|---|---|
| `telegram` | `token`, `chat_id` | @BotFather creates the bot. Write to it, then read your chat id at `https://api.telegram.org/bot<TOKEN>/getUpdates` |
| `discord` | `url` | Channel settings > Integrations > Webhooks |
| `ntfy` | `server`, `topic`, `token` (optional) | Install the ntfy app and subscribe to a topic. On the public server, the topic name is the only protection: make it long and random |
| `slack` | `url` | api.slack.com/apps > your app > Incoming Webhooks |
| `email` | `host`, `port`, `user`, `password`, `from`, `to` | Your mail provider. Port 587 uses STARTTLS, 465 uses TLS from the start |
| `webhook` | `url`, `token` (optional) | Any service accepting a JSON POST |
| `whatsapp` | `phone_id`, `token`, `to`, `template`, `template_lang`, `api_version` | A Meta developer app with the WhatsApp product |

### Generic webhook payload

```json
{"title": "...", "body": "...", "level": "warning", "project": "myapp", "host": "server-1", "timestamp": 1700000000}
```

### WhatsApp: read this first

WhatsApp is the hardest channel to keep reliable for alerts:

- Plain text is only delivered **within 24 hours after you last wrote to the
  business number**. After that, Meta silently refuses it.
- To receive alerts at any time you need a **message template**, approved by
  Meta, with two body variables. helpoupou fills `{{1}}` with the title and
  `{{2}}` with the body. Set its name in `template`.
- Access tokens from the developer console expire quickly. Use a permanent
  system-user token.
- `api_version` defaults to `v21.0`. Meta retires old versions: check the
  current one in the Meta developer documentation.

For server alerts, Telegram or ntfy are simpler and more dependable.

## Adding a provider

Create `lib/notify/<name>.sh` with four functions and add the name to
`NOTIFY_PROVIDERS` in `lib/notify.sh`:

| Function | Role |
|---|---|
| `notify_<name>_label` | One line shown in the wizard |
| `notify_<name>_help` | Two or three lines: where to get the credentials |
| `notify_<name>_fields` | One line per setting: `key\|Label\|secret(0/1)\|default\|opt` |
| `notify_<name>_send CHANNEL` | Deliver `N_TITLE`, `N_BODY`, `N_LEVEL`; return 0 on success |

Read settings with `nget "$ch" key`, build the payload in a file from
`mktmp`, and call `notify_http URL PAYLOAD_FILE [curl config lines]`.
