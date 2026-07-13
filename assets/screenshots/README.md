# Screenshots

Proof for each step of the build. Where a password showed up on screen, it's blacked out.

## Step 0 — getting ready
- `00-utm-vm-list.png` — the VM list in UTM
- `00-utm-winserver.png` — the Windows Server VM (DC01) running
- `00-utm-win11client.png` — the Windows 11 client VM (WS01) running; shows its Guest IP
  `192.168.100.20` and the Shared Network setup
- `00-utm-ubuntuserver.png` — the Ubuntu (Wazuh) VM running. All three VMs are visible in the
  sidebar as QEMU machines on the same Shared Network — the networking setup that finally worked

## Step 1 — the domain controller (DC01)
- `01-dc01-ip.png` — DC01's fixed IP address, set in PowerShell
- `01-get-addomain.png` — `Get-ADDomain`, confirming the domain `lab.local` is up
- `01-dns-console.png` — the DNS console showing the `lab.local` zone
- `01-test-users.png` — the test users and folders (OUs) in Active Directory
- `01-svc-sql-spn.png` — the `svc-sql` account with its SPN (the target for a later attack)
- `01-server-edition.png` — `Get-ComputerInfo` on DC01, confirming Windows Server 2025 Standard
- `01-client-edition.png` — `winver` on WS01, confirming Windows 11 Pro

## Step 2 — the client (WS01)
- `02-lab-login.png` — signed in as a domain account (`whoami` shows `lab\...` and the AD groups)
- `02-ws01-dns.png` — WS01 using DC01 for DNS, and `nslookup lab.local` resolving cleanly

## Step 3 — Wazuh (the SIEM)
- `03-wazuh-install-done.png` — the installer finishing (admin password blacked out)
- `03-dashboard-login.png` — the Wazuh dashboard
- `03-agents-active.png` — both agents (DC01 and WS01) showing as active
- `03-sysmon-events.png` — a Sysmon-based alert opened up, showing the raw Sysmon fields behind it

## Step 4 — validation
- `04-failed-login-alert.png` — a failed-logon alert opened up, showing the event details
  (target user, the wrong-password code, the MITRE tag)
- `04-overview.png` — the Threat Hunting dashboard: total events, alert severities, top MITRE
  ATT&CK techniques, and alert volume across all agents
