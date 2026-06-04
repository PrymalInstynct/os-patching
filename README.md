Role Name
=========

This Ansible role will apply missing OS patches, send a notification via Discord web hook, and reboot the hosts.

- **NOTE:** Assumes a user account with passwordless sudo is used to execute the playbook

Requirements
------------

### Collections
  - community.general
  - community.docker

Dependencies
------------

### Ansible Host
  - Docker SDK for Python
    - python3-docker is a typical package name

### Inventory Hosts
  - Docker and Docker-Compose
    - debian 12 packages
      - docker.io
      - docker-compose

Role Variables
--------------

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

```

### vars/vault.yml
```yaml
---
vault_discord_webhook_id: 0000000000000
vault_discord_webhook_token: xxxxxxxxxxxxxxxx

```

Example Inventory
-----------------

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
Example Playbook
----------------

`ansible-playbook -i inventory.yml apply-patches.yml -K --ask-vault-pass`

```yaml
---
- name: Update Infrastructure Nodes & Perform a reboot
  hosts: all
  roles:
    - { role: os-patching }

```

Pending Restart Reminders
-------------------------

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

License
-------

MIT

Author Information
------------------

[Chad Zimmerman](https://github.com/PrymalInstynct)
