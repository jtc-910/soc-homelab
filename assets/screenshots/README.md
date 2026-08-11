# Screenshots

Proof for each step of the build. Where a password showed up on screen, it's blacked out.

Naming: each file starts with the name of the folder/doc it belongs to (`lab-setup-`, `ad-lab-`,
`siem-wazuh-`, `incident-`, `validation-`), followed by the step number within that doc. This is so
files from different areas don't collide just because they happen to share a step number.

## lab-setup (00-lab-setup.md) — getting ready
- `lab-setup-00-utm-vm-list.png` — the VM list in UTM
- `lab-setup-00-utm-winserver.png` — the Windows Server VM (DC01) running
- `lab-setup-00-utm-win11client.png` — the Windows 11 client VM (WS01) running; shows its Guest IP
  `192.168.100.20` and the Shared Network setup
- `lab-setup-00-utm-ubuntuserver.png` — the Ubuntu (Wazuh) VM running. All three VMs are visible in
  the sidebar as QEMU machines on the same Shared Network — the networking setup that finally worked

## ad-lab/01-domain-setup.md — the domain controller (DC01)
- `ad-lab-01-dc01-ip.png` — DC01's fixed IP address, set in PowerShell
- `ad-lab-01-get-addomain.png` — `Get-ADDomain`, confirming the domain `lab.local` is up
- `ad-lab-01-dns-console.png` — the DNS console showing the `lab.local` zone
- `ad-lab-01-test-users.png` — the test users and folders (OUs) in Active Directory
- `ad-lab-01-svc-sql-spn.png` — the `svc-sql` account with its SPN (the target for a later attack)
- `ad-lab-01-server-edition.png` — `Get-ComputerInfo` on DC01, confirming Windows Server 2025 Standard

## ad-lab/03-gpo-hardening.md — audit-logging group policy
- `ad-lab-03-gpo-created.png` — the new GPO in GPMC, linked to the domain
- `ad-lab-03-audit-categories.png` — the three enabled audit categories in the GPO editor
- `ad-lab-03-commandline-logging.png` — "include command line" setting turned on
- `ad-lab-03-gpupdate-forced.png` — `gpupdate /force` applying the new policy
- `ad-lab-03-process-creation-event.png` — a real 4688 event in Wazuh with the command line visible

## ad-lab/04-client-join-least-privilege.md — the client (WS01) and least privilege
- `ad-lab-04-client-edition.png` — `winver` on WS01, confirming Windows 11 Pro
- `ad-lab-04-lab-login.png` — signed in as a domain account (`whoami` shows `lab\...` and the AD groups)
- `ad-lab-04-ws01-dns.png` — WS01 using DC01 for DNS, and `nslookup lab.local` resolving cleanly
- `ad-lab-04-local-admins.png` — the local Administrators group on WS01, no domain test users in it
- `ad-lab-04-least-privilege-denied.png` — a standard domain user denied when trying an admin action

## siem-wazuh/01-wazuh-deployment.md — Wazuh (the SIEM)
- `siem-wazuh-01-install-done.png` — the installer finishing (admin password blacked out)
- `siem-wazuh-01-dashboard-login.png` — the Wazuh dashboard
- `siem-wazuh-01-agents-active.png` — both agents (DC01 and WS01) showing as active
- `siem-wazuh-01-sysmon-events.png` — a Sysmon-based alert opened up, showing the raw Sysmon fields
  behind it

## 04-validation.md and incident-writeups/01-bruteforce.md — validation and the write-up
- `incident-01-failed-login-alert.png` — a failed-logon alert opened up, showing the event details
  (target user, the wrong-password code, the MITRE tag)
- `validation-04-overview.png` — the Threat Hunting dashboard: total events, alert severities, top
  MITRE ATT&CK techniques, and alert volume across all agents

## ad-lab/02-users-and-groups.md — users, groups, and OUs (continued)
- `ad-lab-02-ou-structure.png` — the four OUs alongside the Windows default containers in ADUC

## ad-lab/05-fileserver-acls.md — file server and NTFS permissions
- `ad-lab-05-ntfs-permissions.png` — NTFS permissions on a department folder, only the matching group
  and Domain Admins
- `ad-lab-05-access-granted.png` — a user accessing their own department's share
- `ad-lab-05-access-denied.png` — the same user denied on a different department's share

## siem-wazuh/02-patch-management.md — updating Wazuh (4.14.6 to 4.14.7)
- `siem-wazuh-02-update-available.png` — apt showing the three Wazuh packages as upgradable
- `siem-wazuh-02-updated-version.png` — `wazuh-control info` showing the new version after the upgrade
- `siem-wazuh-02-agents-after-update.png` — both agents still active after the update

## linux-lab/01-ssh-hardening.md — hardening the Wazuh VM (SSH, Fail2ban)
- `linux-lab-01-sshd-config.png` — `PasswordAuthentication no` and `PermitRootLogin no` set in
  `sshd_config`
- `linux-lab-01-cloud-init-config-change.png` — the same setting fixed in the cloud-init override
  file that was actually winning
- `linux-lab-01-key-login-working.png` — successful SSH login using the key, no password prompt
- `linux-lab-01-password-login-denied.png` — a password-only login attempt refused outright
- `linux-lab-01-fail2ban-status.png` — `fail2ban-client status sshd` showing the jail active
- `linux-lab-01-fail2ban-banned.png` — my own IP address showing up as banned after a few failed
  attempts
- `linux-lab-01-fail2ban-connection-refused.png` — a new SSH connection refused while banned
- `linux-lab-01-fail2ban-unbanned.png` — the IP removed from the ban list again
- `linux-lab-01-ufw-status.png` — `ufw status verbose`, only SSH/1514/1515/443 open, restricted to
  the lab subnet
- `linux-lab-01-services-disabled.png` — no failed services after disabling ModemManager,
  multipathd, and udisks2
- `linux-lab-01-unattended-upgrades-dryrun.png` — `unattended-upgrade --dry-run` confirming only
  security-origin packages get installed automatically

## ad-lab/07-dhcp.md — DHCP on DC01
- `ad-lab-07-dhcp-verify.png` — the DHCP console showing the active Lab-Network scope
  (192.168.100.100–200)
- `ad-lab-07-dhcp-lease.png` — an active lease for WS01 after temporarily switching it to DHCP

## Still to add
- Nothing outstanding right now.
