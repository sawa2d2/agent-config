# Isolating agent work under a dedicated user

General procedure for running development and coding-agent work (agent CLIs,
tmux, worktrees) as a dedicated unprivileged Linux user, so that a misbehaving
agent cannot read the main user's files or credentials or act as root. Commands
run as an administrator with `sudo`; `dev` is the example user and `alice` the
main user. Each step ends with a verification command.

A separate user isolates files and processes, not the kernel or the network:
it can still read world-readable files, see other users' processes in `ps`,
and reach services listening on localhost. Use the options in
[Stronger isolation](#stronger-isolation) when that matters.

## 1. Create the user and group

```sh
sudo useradd -m -U -s /bin/bash dev   # or on Debian/Ubuntu: sudo adduser --disabled-password dev
sudo passwd -l dev                    # no password login; use SSH keys or sudo -iu dev
```

Add no supplementary groups unless a task needs one. `sudo` and `wheel` grant
sudo, `adm` and `systemd-journal` read system logs, and `disk` gives raw
block-device access. `docker` is equivalent to root: anyone who can talk to
the Docker daemon can run `docker run -v /:/host` and write to the host as
root. `libvirt`, `lxd` and `incus` are root-equivalent for the same reason:
they can start a VM or container with a host disk or directory attached.
Prefer rootless containers (below) or a user-session VM (`qemu:///session`).

```sh
id dev   # expect only: groups=NNNN(dev)
```

## 2. Private home directories

Make every home directory, including the main user's, mode 700, and make new
ones private by default:

```sh
sudo chmod 700 /home/*                                    # only user homes should live here
sudo sed -i 's/^#\?HOME_MODE.*/HOME_MODE\t0700/' /etc/login.defs   # useradd (shadow 4.8+)
grep -q '^HOME_MODE' /etc/login.defs || echo 'HOME_MODE 0700' | sudo tee -a /etc/login.defs
sudo sed -i 's/^#\?DIR_MODE=.*/DIR_MODE=0700/' /etc/adduser.conf   # Debian adduser only
```

`UMASK` in `/etc/login.defs` sets the default umask where `pam_umask` is
enabled (Debian/Ubuntu) and is also the fallback for `HOME_MODE`. With
`USERGROUPS_ENAB yes`, `pam_umask` relaxes it to 002 for users whose primary
group has their own name, so files become group-writable. Set the
dev user's umask to 077 (private) or 027 (group-readable) in its shell profile
so new files are not world-readable:

```sh
echo 'umask 077' | sudo -u dev tee -a /home/dev/.profile /home/dev/.bashrc >/dev/null
```

```sh
stat -c '%a %U %n' /home/*            # expect 700 for every home
sudo -iu dev sh -c umask              # expect 0077 (or 0027)
sudo -u dev find /home/dev -perm /022 ! -type l | head   # review group/world-writable files
sudo -u dev ls /home/alice            # expect: Permission denied
```

## 3. sudo

Prefer no sudo at all for the dev user. If it needs specific privileged
commands, grant exactly those in a drop-in, edited with `visudo` so syntax is
checked before the file is saved:

```sh
sudo visudo -f /etc/sudoers.d/dev
```

```sudoers
dev ALL=(root) /usr/bin/systemctl restart myapp.service
```

- Use full paths and fixed arguments. Avoid `ALL`, `NOPASSWD: ALL`, and
  wildcards (`*` matches spaces and extra arguments).
- Avoid commands with shell escapes or arbitrary file access: editors, pagers,
  `find`, `env`, interpreters, `tar`, `systemctl edit`, and any script the dev
  user can write.
- Keep `Defaults secure_path` (default in most distributions) so the user's
  `PATH` is not used for sudo, and do not add user-writable directories to it.
- Files in `/etc/sudoers.d` whose names contain `.` or end in `~` are ignored.

```sh
sudo chmod 0440 /etc/sudoers.d/dev
sudo visudo -c                        # expect: parsed OK for every file
sudo -l -U dev                        # expect only the intended commands
```

## 4. SSH access

Use a key dedicated to the dev user, never the main user's key, and disable
forwarding so the dev session cannot use the client's agent or tunnels:

```sh
sudo install -d -m 700 -o dev -g dev /home/dev/.ssh
echo 'no-agent-forwarding,no-X11-forwarding ssh-ed25519 AAAA... dev@laptop' |
  sudo install -m 600 -o dev -g dev /dev/stdin /home/dev/.ssh/authorized_keys
```

In `/etc/ssh/sshd_config` (or a file in `/etc/ssh/sshd_config.d/`), restrict
logins and tighten the dev user:

```
AllowUsers alice dev
Match User dev
    PasswordAuthentication no
    AllowAgentForwarding no
    X11Forwarding no
```

`AllowUsers` rejects every user not listed, so include all users who need SSH
before reloading. On the client, keep `ForwardAgent no` for the dev host.

```sh
sudo sshd -t && sudo systemctl reload ssh     # sshd on RHEL-family systems
sudo sshd -T -C user=dev,host=localhost,addr=127.0.0.1 | grep -E 'agentforwarding|x11forwarding|passwordauthentication'
ssh -o IdentitiesOnly=yes -i ~/.ssh/id_dev dev@host 'ssh-add -l'   # expect: Could not open a connection
```

A forwarded agent lets every process of the dev user sign with the client's
keys while the session is open, so check this from inside the tmux session
the agents run in, not only from a fresh login. Debian-family `sshd_config`
ships `X11Forwarding yes`, so the `Match` block is needed even on defaults.
```

## 5. Credentials

Give the dev user only its own, minimal credentials, created for it:

- A separate SSH key or fine-grained token for Git hosting, limited to the
  repositories it works on (deploy key or fine-grained personal access token
  with expiry); log in to `gh` and similar CLIs as the dev user.
- Separate agent and model API keys with spend limits, revocable on their own.
- No copies or symlinks of the main user's `~/.ssh`, `~/.aws`,
  `~/.config/gcloud`, `~/.kube`, `~/.docker/config.json`, `~/.netrc`, browser
  profiles or password-manager sessions, and no shared `SSH_AUTH_SOCK`.

```sh
sudo -iu dev sh -c 'ls -a ~ ~/.config; env | grep -iE "token|key|secret|auth_sock"'
sudo -iu dev ssh -T git@github.com    # expect the dev identity, not the main user's
```

## 6. systemd user services and lingering

Enable lingering only if dev's user services or tmux sessions must keep
running without a login session (with `KillUserProcesses=yes` in
`logind.conf`, processes are otherwise killed at logout):

```sh
sudo loginctl enable-linger dev       # undo: sudo loginctl disable-linger dev
loginctl show-user dev -p Linger      # expect Linger=no unless needed
```

## 7. Network services

Any service listening on localhost or a LAN address is reachable by the dev
user. Require authentication on local model servers, dev servers and
databases, or bind them where the dev user does not need them, and do not
expose management sockets such as libvirt's TCP listener.

```sh
sudo ss -ltnp                         # review every listener and its owner
```

## Stronger isolation

- Rootless Podman or rootless Docker run containers inside the dev user's
  user namespace, without root equivalence. Check the prerequisites with
  `grep dev /etc/subuid /etc/subgid` and `sysctl kernel.unprivileged_userns_clone`
  (expect 1 where the sysctl exists).
- A VM or a remote development host separates the kernel, network and
  filesystem entirely; use it for untrusted code or unattended agents with
  broad permissions.
- `hidepid=invisible` on `/proc` hides other users' processes, and a host
  firewall (for example nftables `meta skuid`) can restrict the dev user's
  network access.
