# helpoupou

One command to run, deploy and watch small Docker Compose projects.

Install it once per machine. Each project only carries a small `helpoupou.conf`.
The same command does the right thing on a dev workstation and on a production
server.

- **Guided menu**: `helpoupou`, and pick. Every entry is also a subcommand.
- **Dev or prod, automatically**: asked once per machine, then remembered.
- **Env file handled**: created from the example, secrets generated, never overwritten.
- **Production guards**: refuses the example domain, waits for healthy services.
- **Doctor**: Docker, RAM, disk, busy ports, missing memory limits, pending reboot, failed timers, SSH still open to passwords, alerts that reach nobody.
- **Notifications**: Telegram, Discord, ntfy, Slack, e-mail, WhatsApp, or any webhook. Several at once, each with its own minimum level.

Bash only. Needs Docker with Compose v2, `curl` and `openssl`. Linux.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/elopin42/helpoupou/main/install.sh | bash
```

Or from a clone: `./install.sh`. Update later with `helpoupou self-update`.

## Quick start

```sh
cd myapp            # a project with a compose file
helpoupou init      # writes helpoupou.conf
helpoupou           # opens the menu
```

## Commands

| Command | What it does |
|---|---|
| `helpoupou` | Menu |
| `up` | Check, prepare the env file, build and start |
| `down` / `restart` / `build` / `ps` | Lifecycle |
| `logs [service]` / `shell [service]` | Look inside |
| `env` / `env check` | Create the env file, list what is missing (names only) |
| `clean` | Delete containers and volumes, after confirmation |
| `doctor` | Health report |
| `notify setup` / `list` / `test` / `send` / `remove` | Notification channels |
| `mode [dev\|prod]` | Show or set what this machine is |
| `init` | Create `helpoupou.conf` |

Options: `--mode dev|prod`, `--force`, `--yes`, `-C DIR`.

Without a terminal (CI, timers), commands never wait for input: they fail with
a message naming what is missing.

## Project-specific steps

Put executables in `.helpoupou/hooks/` of your project: `pre-up`, `post-up`,
`first-boot`, `pre-down`. That is where creating an admin account or loading
demo data belongs. helpoupou itself stays generic.

## Documentation

- [docs/CONFIG.md](docs/CONFIG.md): every key of `helpoupou.conf`, and hooks
- [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md): providers and their settings

## Tests

```sh
tests/run.sh
```

No Docker and no network needed: external commands are replaced by test doubles.
