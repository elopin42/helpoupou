# To do later

Short list of what is not built yet, in the order it should be done.

## 1. Try it for real

Everything below was only tested against test doubles. First real runs:

- [ ] `Start` on a real project in dev mode
- [ ] `Deploy` on a real server in prod mode
- [ ] One real notification per provider actually used
- [ ] Create a key on a real security key, and `Import` on a second machine
- [ ] `Install my keys on a server`, then `Turn SSH passwords off` and `Confirm`
- [ ] Let the automatic rollback fire once on purpose, to see passwords come back

## 2. AI assistant

A menu entry `AI assistant ›`. helpoupou writes the text, it never calls an AI itself.

- [ ] Write an `AGENTS.md` into a project: how it starts, where project-specific steps go (hooks), what not to touch
- [ ] Ready-to-paste prompts built from what helpoupou detects, copied to the clipboard:
  - [ ] Adapt this project to helpoupou (read the Makefile and scripts, write `helpoupou.conf`, move specifics into hooks)
  - [ ] Fix what `doctor` found (prompt carries the real warnings)
  - [ ] Improve the project (missing health checks, memory limits, example env gaps)
  - [ ] Read-only server report (machine, containers, ports, certificates, timers, backups, security)
- [ ] Optional: open an installed AI CLI directly with the chosen prompt
- [ ] Never put secret values in a prompt: variable names only
- [ ] An `AGENTS.md` for this repository (bash only, nothing private, tests required)

## 3. Production

- [ ] Guided first install of a server: one questionnaire, then everything runs; re-running resumes where it stopped
- [ ] Backups: full daily, database hourly, written under a temporary name and renamed only on success
- [ ] Off-site copy, encrypted. Must be configured or explicitly refused, never silently absent
- [ ] Restore drill: restore the latest backup into a throwaway database and report
- [ ] Backup before every redeploy that runs migrations
- [ ] systemd timers installed and removed by helpoupou
- [ ] Monitor on a timer: containers, disk, RAM, backup freshness. Alert only when a state changes
- [ ] Daily recap message
- [ ] Auto-deploy on push, only when CI is green
- [ ] Rollback to an earlier commit
- [ ] Firewall and basic hardening: swap on small machines, security updates, fail2ban

## 4. Several projects on one server

- [ ] One edge reverse proxy owned by helpoupou: TLS and routing by hostname, each project plain HTTP behind it
- [ ] Server view: every project with containers, memory, disk, backup age
- [ ] One monitor and one status page for all projects instead of one per project
- [ ] Expiry watch with alerts ahead of time: TLS certificates, domain names, deploy keys, API tokens declared by a project

## 5. Move existing projects over

- [ ] Start with the simplest project, in dev only
- [ ] Then one production project at a time, keeping its old Makefile until helpoupou has run a full deploy and a restore drill

## Smaller things

- [ ] CI: ShellCheck at warning level and `shfmt` (today only errors block)
- [ ] Pick a license
- [ ] `sudo` with a security key on a workstation (optional, never on a server over SSH)
- [ ] Menu in a narrow terminal: long project paths wrap
- [ ] WhatsApp provider: confirm the current API version against the official documentation
