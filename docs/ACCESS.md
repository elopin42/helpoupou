# Security keys and SSH access

Goal: log in to your servers with a hardware security key (YubiKey or any
FIDO2 key), and turn password logins off without any risk of locking yourself
out.

## On your workstation

```sh
helpoupou key setup primary     # plug the first key, enter its PIN, touch it
helpoupou key setup backup      # swap keys, repeat
helpoupou key list
helpoupou key push user@server  # install every registered key on a server
helpoupou key github            # use them for GitHub
```

| Command | What it does |
|---|---|
| `key setup [name]` | Creates an SSH key on the device and makes `ssh` use it |
| `key import` | On a new machine: rebuilds the key handles from the device |
| `key adopt FILE.pub` | Registers a security key you created yourself |
| `key list` | Registered keys, and security keys found but not registered |
| `key push USER@HOST` | Adds your keys to the server, then tests a key login |
| `key github` | Adds the keys to your GitHub account; commit signing is optional |

Things to know:

- **Register at least two keys.** One can be lost or broken. helpoupou warns
  while you have a single one, and refuses to harden a server with one.
- **The key needs a PIN.** If creation fails, set it first with
  `ykman fido access change-pin` (YubiKey) or `fido2-token -S <device>`.
- **The file in `~/.ssh` is only a handle.** It is useless without the
  physical key. `key import` recreates it anywhere from the device.
- **"PIN at every use"** (the default) means PIN and touch for each login.
  Answer no to require only a touch.
- helpoupou adds one line, `Include ~/.ssh/helpoupou.conf`, at the top of your
  `~/.ssh/config`, after asking. Everything else in that file is untouched.
- Requires OpenSSH 8.2 or newer on both sides.

## On the server

```sh
helpoupou ssh status
helpoupou ssh harden
# then, from a NEW terminal, logged in with your key:
helpoupou ssh confirm
```

`ssh harden` disables password logins. It is built so that it cannot lock you
out:

1. It refuses unless **two keys** are installed for your account
   (`--allow-single-key` to accept the risk).
2. It refuses unless the server log shows that **your current session logged
   in with a key**. Typing a password to get in proves nothing.
3. It validates the new configuration with `sshd -t`, then checks that
   passwords are really off. If another file still enables them, it undoes
   its change and tells you.
4. It arms an **automatic rollback**: unless you run `helpoupou ssh confirm`
   from a new session within 10 minutes, passwords come back by themselves.
   Confirming from the session that did the hardening is refused, because
   that session proves nothing.

`ssh unharden` removes helpoupou's settings at any time.

What it writes: `/etc/ssh/sshd_config.d/00-helpoupou.conf`.

```
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
```

## Limits

- **Unattended jobs cannot use a security key**: nobody is there to touch it.
  A server that pulls from git on a timer keeps a normal, read-only deploy key.
- **`sudo` on a server cannot be tied to your security key over SSH**: the
  key is plugged into your workstation, not the server.
- Needs `sudo`, systemd and a distribution whose sshd reads
  `/etc/ssh/sshd_config.d/` (Debian, Ubuntu and most current ones).
