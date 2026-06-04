# os-patching

A single Ansible role that applies all available OS package updates, updates/restarts Docker Compose stacks, sends Discord notifications about what happened, and reboots the host if the OS reports a reboot is required. Hosts are patched one at a time (`serial: 1`) to ensure a reboot never takes out the whole fleet. Assumes the connecting user has **passwordless sudo**.

## Requirements

### Collections

- `community.general`
- `community.docker`

Versions are pinned in `collections/requirements.yml`.

### Control Node

- Docker SDK for Python (`python3-docker`)

### Managed Hosts (Docker-enabled)

- Docker
- Docker Compose

## Role Variables

### defaults/main.yml

```yaml
---
discord_webhook_id: "{{ vault_discord_webhook_id }}"
discord_webhook_token: "{{ vault_discord_webhook_token }}"
# Docker Compose stacks are auto-discovered per host via `docker compose ls`.
# List any stack directories to skip here — most importantly the automation
# controller's own stack (e.g. Semaphore), which must not be patched mid-run.
compose_exclude:
  - /opt/stacks/semaphore
aur_helper: yay
# When false, hosts are patched but never rebooted (reboot-required signals persist).
reboot_enabled: true
# Per-host override: when true, the host is patched but never rebooted and no
# reboot-pending notice is sent (e.g. workstations in the devices_net group).
reboot_skip: false
```

**Variable Details:**

- `discord_webhook_id` / `discord_webhook_token`: Mapped from vault secrets. Required for Discord notifications.
- `compose_exclude`: List of Docker Compose stack directories to pull but never restart. Typically includes the automation controller's own stack (e.g. `/opt/stacks/semaphore`) — restarting it mid-run would break the playbook execution.
- `aur_helper`: AUR wrapper used on Arch Linux (default `yay`). Used for patching AUR packages and installing `needrestart`.
- `reboot_enabled`: Global toggle. When `false`, all hosts are patched but never rebooted. Reboot signals persist, so a later run with `reboot_enabled: true` will reboot them.
- `reboot_skip`: Per-host override. When `true`, the host is patched but never rebooted and no reboot-pending notice is sent. Automatically set for hosts in the `devices_net` group on Arch Linux.

### Secrets: vars/vault.yml

`vars/vault.yml` is encrypted with `ansible-vault`. It exposes:

```yaml
---
vault_discord_webhook_id: 0000000000000
vault_discord_webhook_token: xxxxxxxxxxxxxxxx
```

Edit with: `ansible-vault edit roles/os-patching/vars/vault.yml`

## Per-OS Behavior

### Package Upgrades

- **Debian**: `apt full-upgrade`
- **RedHat** (Fedora, EL): `dnf upgrade -y latest`
- **Arch Linux**: `pacman -Syu` (system) + AUR via `{{ aur_helper }}` as `ansible_user`

### Reboot Detection

Reboot detection mechanism varies by OS:

- **Debian**: Checks `/var/run/reboot-required`
- **RedHat**: Runs `needs-restarting -r`; reboot when exit code is `1`
- **Arch Linux**: Parses `needrestart -b NEEDRESTART-KSTA` output

### Arch-Specific Behavior

- AUR packages are patched as `ansible_user` via `{{ aur_helper }}` (default `yay`)
- Hosts in the `devices_net` group (workstations) automatically skip reboot and do not send reboot-pending notices (set via `reboot_skip: true`)
- The role pre-installs `needrestart` on Arch, and `dnf-utils` on RedHat

## Docker Compose Handling

Docker stacks are auto-discovered per host via `docker compose ls --format json`. The role partitions discovered stacks into two categories:

1. **Fully Managed** (discovered minus `compose_exclude`): Images are pulled with `pull: always` and stacks are recreated (`docker compose up -d`).
2. **Pull-Only** (discovered ∩ `compose_exclude`): Images are pulled but stacks are **never** restarted. This protects the automation controller's own stack from being torn down mid-run.

### Pending-Restart Detection

The role detects when stacks are running outdated images (drift-based): it compares each running container's image ID against the latest image ID locally available for its tag. A mismatch means a newer image was pulled but not applied. When detected, a Discord embed lists the stale stacks. This is self-clearing once `docker compose up -d` is run.

## Discord Notifications

The role sends Discord embeds for:

- OS patches applied (with count)
- OS patches not required (no-op)
- Docker images updated (with count)
- Stacks with pending restarts (drift detected)
- Docker stack errors (if any)
- Host reboot (if triggered)

All notifications use the webhook credentials from `vault.yml`.

## Commands

### Install Collections

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

### Apply Patches (Full Run)

```bash
ansible-playbook -i inventory.yml apply-patches.yml -K --ask-vault-pass
```

Flags:
- `-K`: Prompt for become (sudo) password
- `--ask-vault-pass`: Prompt for Ansible vault password
- `--check`: Dry-run mode (add to preview changes)
- `--limit <hostname>`: Run against a single host

### Report Pending Restarts (Read-Only)

```bash
ansible-playbook -i inventory.yml report-pending-restarts.yml -K --ask-vault-pass
```

This reads-only playbook discovers stacks and reports (via Discord) any with outdated images. It does not patch, pull, or restart anything — safe to run as often as needed. Useful as a daily scheduled reminder.

### Lint & Syntax Check

```bash
ansible-lint
ansible-playbook apply-patches.yml --syntax-check
```

### Edit Encrypted Secrets

```bash
ansible-vault edit roles/os-patching/vars/vault.yml
```

## Example Inventory

```yaml
---
infrastructure:
  children:
    management_net:
      hosts:
        provision01:
          ansible_host: 10.10.10.30
    devices_net:
      hosts:
        wks01:
          ansible_host: 10.10.100.10
    development_net:
      hosts:
        dev01:
          ansible_host: 10.10.111.200

```

## Pending Restart Reminders

Stacks listed in `compose_exclude` (e.g. the automation controller's own stack) get their images
pulled during patching but are never restarted automatically. `report-pending-restarts.yml` is a
read-only playbook that reports — via Discord — any stack running an outdated image (a newer image
was pulled but not applied). It does not patch, pull, or restart anything, and is self-clearing
once the stack is restarted with `docker compose up -d`. Schedule it daily (e.g. a Semaphore
template schedule) as a recurring reminder.

`ansible-playbook -i inventory.yml report-pending-restarts.yml -K --ask-vault-pass`

### Scheduling in Semaphore

Create a **separate template** for this playbook (don't reuse the patching template) and give it a
**daily schedule**:

1. **Task Template** → Playbook: `report-pending-restarts.yml`, same inventory/repository/environment
   as your patching template.
2. **Vault Password** — attach the **same** vault secret your `apply-patches.yml` template uses.
   This is required: the playbook decrypts `vault.yml` for the Discord webhook credentials, and
   without it the run fails with `Attempting to decrypt but no vault secrets found`.
3. **Become / sudo password** — supply it the same way the patching template does (the playbook
   runs `become: true` so it can read every stack's containers).
4. **Schedule** — add a cron schedule on the template (e.g. `0 7 * * *` for 07:00 daily).

The run is read-only — it never patches, pulls, or restarts — so it is safe to run as often as
you like. It keeps re-sending the reminder until the stale stack is restarted.

## License

MIT

## Author

[Chad Zimmerman](https://github.com/PrymalInstynct)
