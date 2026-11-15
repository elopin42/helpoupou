# Configuration

## `helpoupou.conf`

Lives at the root of your project. Plain `KEY=value` lines. The file is
**parsed, never executed**: no variable expansion, no command substitution.
Unknown keys are reported and ignored. `helpoupou init` writes a first version.

| Key | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | directory name | Shown in the menu and in notifications |
| `COMPOSE_DEV` | compose default | Compose files used in dev mode, space-separated |
| `COMPOSE_PROD` | compose default | Compose files used in prod mode, space-separated |
| `COMPOSE_DEV_PROFILES` | none | Compose profiles enabled in dev |
| `COMPOSE_PROD_PROFILES` | none | Compose profiles enabled in prod |
| `ENV_FILE` | `.env` | The env file helpoupou maintains |
| `ENV_EXAMPLE` | `.env.example` | Its template, committed in your repo |
| `SECRETS` | none | Secrets to generate, see below |
| `DB_VOLUME` | none | Docker volume of the database. Absent means first boot |
| `DOMAIN_KEY` | none | Env variable holding the public hostname |
| `PROD_ENV_OVERRIDES` | none | `KEY=value` pairs forced into the env file in prod |
| `URLS_DEV` / `URLS_PROD` | none | Printed after a start |
| `SHELL_SERVICE` | none | Default service for `helpoupou shell` |
| `LOG_SERVICE` | all | Default service for `helpoupou logs` |
| `RAM_MIN_MB` | `400` | doctor warns below this much available RAM |
| `DISK_WARN_PCT` | `85` | doctor warns above this disk usage (fails at 95) |

### Secrets

```
SECRETS=SECRET_KEY:64 POSTGRES_PASSWORD:32:db
```

Each entry is `KEY:length`. A value is generated (letters and digits) when the
key is empty or still equal to its value in `ENV_EXAMPLE`. A value you set
yourself is never touched.

Add `:db` for a database password. Once `DB_VOLUME` exists, the database was
initialised with the current password, so helpoupou refuses to regenerate it
and tells you instead.

List only secrets helpoupou may invent. API keys given by a third party do not
belong here.

### Production guards

- `DOMAIN_KEY`: in prod, `up` stops if that variable is empty or still the
  example value. Override once with `HELPOUPOU_ALLOW_TEMPLATE_DOMAIN=1`.
- `PROD_ENV_OVERRIDES=DEBUG=0 FORCE_HTTPS=1`: written into the env file on
  every prod start.
- Prod starts with `--wait`: `up` succeeds only when services are healthy.
- `clean` in prod asks you to type the project name and never runs unattended.

## Hooks

Executables in `.helpoupou/hooks/`, run from the project root.

| Hook | When |
|---|---|
| `pre-up` | Before building and starting |
| `first-boot` | After the first start, only if `DB_VOLUME` did not exist before |
| `post-up` | After every start |
| `pre-down` | Before stopping |

They receive `HELPOUPOU_MODE` (`dev` or `prod`), `HELPOUPOU_PROJECT` and
`HELPOUPOU_COMPOSE` (the full compose command for the current mode). A missing
hook is skipped. A hook that exits non-zero stops the command with that code.

```sh
#!/usr/bin/env bash
# .helpoupou/hooks/first-boot
set -euo pipefail
$HELPOUPOU_COMPOSE exec -T web ./create-admin
```

## Machine settings

Stored in `~/.config/helpoupou/` (or `$XDG_CONFIG_HOME/helpoupou/`).

| File | Content |
|---|---|
| `machine.conf` | `MODE=dev` or `MODE=prod`, asked once on first run |
| `projects` | Projects seen on this machine |
| `notify.conf` | Notification channels (mode 600) |

Environment variables:

| Variable | Effect |
|---|---|
| `HELPOUPOU_MODE` | Mode for this run (same as `--mode`) |
| `HELPOUPOU_YES=1` | Accept defaults (same as `--yes`) |
| `HELPOUPOU_RAM_MIN_MB`, `HELPOUPOU_DISK_WARN_PCT` | doctor thresholds for the machine |
| `HELPOUPOU_ALLOW_TEMPLATE_DOMAIN=1` | Skip the production domain guard |
| `HELPOUPOU_HTTP_TIMEOUT` | Seconds before a notification call gives up (15) |
