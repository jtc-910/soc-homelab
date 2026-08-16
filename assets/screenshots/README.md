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

## ad-lab/03-gpo-hardening.md — audit-logging group policy, USB blocking, screen lock, PowerShell logging, password policy
- `ad-lab-03-gpo-created.png` — the new GPO in GPMC, linked to the domain
- `ad-lab-03-audit-categories.png` — the three enabled audit categories in the GPO editor
- `ad-lab-03-commandline-logging.png` — "include command line" setting turned on
- `ad-lab-03-gpupdate-forced.png` — `gpupdate /force` applying the new policy
- `ad-lab-03-process-creation-event.png` — a real 4688 event in Wazuh with the command line visible
- `ad-lab-03-usb-block-registry.png` — registry check on WS01 confirming `Deny_All` is set to 1
- `ad-lab-03-screenlock-registry.png` — registry check on WS01 confirming `InactivityTimeoutSecs` is
  set to 900
- `ad-lab-03-powershell-logging-wazuh-4104.png` — a real 4104 PowerShell Script Block Logging event
  in Wazuh, after fixing the missing event-channel forwarding on the WS01 agent
- `ad-lab-03-password-policy-verified.png` — `Get-ADDefaultDomainPasswordPolicy` output confirming
  complexity, length, age, and history settings

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

## ad-lab/09-dns-deep-dive.md — DNS record types, zone transfers, split-horizon
- `ad-lab-09-dns-records.png` — the DNS record list plus a successful nslookup against the new
  CNAME
- `ad-lab-09-zone-transfer-refused.png` — a zone transfer attempt against lab.local being refused
- `ad-lab-09-split-horizon-internal.png` — nslookup from WS01 resolving portal.lab.local to the
  internal address via DNS Policies

## ad-lab/10-windows-firewall-acls.md — Windows Firewall ACL warm-up
- `ad-lab-10-icmp-allowed.png` — ping from DC01 succeeding after an explicit ICMP allow rule for
  the Domain profile
- `ad-lab-10-icmp-blocked.png` — ping failing again after adding an explicit block rule on top,
  showing block overrides allow
- `ad-lab-10-smb-blocked.png` — SMB access to `\\dc01\IT` blocked from the `abauer` session after an
  outbound TCP/445 firewall rule, added and removed from a separate elevated session

## docker-lab/01-docker-intro.md — Docker on docker01 (formerly the wazuh VM)
- `docker-lab-01-hello-world.png` — `docker run hello-world` succeeding, plus the Compose version

## docker-lab/02-wazuh-migration.md — migrating Wazuh from a native install to Docker
- `docker-lab-02-containers-running.png` — all three Wazuh containers (manager, indexer, dashboard)
  up and stable
- `docker-lab-02-agents-active.png` — DC01 and WS01 both showing Active against the new Docker-based
  manager, using their original client.keys
- `docker-lab-02-dashboard-login.png` — the Wazuh dashboard reachable at https://192.168.100.30,
  served from the container instead of the native install

## docker-lab/03-dvwa-juiceshop.md — DVWA and Juice Shop as Docker attack targets
- `docker-lab-03-dvwa-login.png` — DVWA login page at http://192.168.100.30:8080
- `docker-lab-03-juiceshop-home.png` — Juice Shop home page at http://192.168.100.30:3000

## docker-lab/04-thehive-cortex.md — TheHive + Cortex, and the Wazuh-to-TheHive integration
- `docker-lab-04-ws01-failed-login.png` — WS01's login screen during the brute-force test, showing
  Windows' own credential-guessing throttle message
- `docker-lab-04-wazuh-rule-60204.png` — Wazuh Events filtered to `rule.id : 60204`, two hits from
  WS01 at rule level 10 ("Multiple Windows Logon Failures")
- `docker-lab-04-integrations-log-filtering.png` — `integrations.log` on the Wazuh manager showing
  low-severity events explicitly skipped below the rule-level-6 threshold
- `docker-lab-04-thehive-alert-detail.png` — the resulting TheHive alert detail view: rule 60204,
  level 10, agent WS01, severity Medium
- `docker-lab-04-thehive-alerts-list.png` — TheHive's Alerts overview, showing the full set of alerts
  Wazuh has forwarded so far, including the two from this test
