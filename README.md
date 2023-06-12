Role Name
=========

This Ansible role will apply missing OS patches, send a notification via Discord web hook, and reboot the hosts.

Requirements
------------

### Collections
  - community.general

Role Variables
--------------

### defaults/main.yml
```yaml
---
discord_webhook_id: "{{ vault_discord_webhook_id }}"
discord_webhook_token: "{{ vault_discord_webhook_token }}"

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

License
-------

MIT

Author Information
------------------

[Chad Zimmerman](https://github.com/PrymalInstynct)
