# Automation

## `lab-healthcheck.sh` — is the whole lab actually working?

One command that answers "is everything still the way the docs say it is?" for the entire lab,
instead of trusting that something configured weeks ago is still in place. It came out of the
post-migration audit (2026-10-10): several things the write-ups described as done had quietly not
survived the rebuild onto Proxmox, and one container reported `Up` while not serving anything at
all (see [docker-lab/03-dvwa-juiceshop.md](../docker-lab/03-dvwa-juiceshop.md)). Both kinds of
problem are only caught by checking the real thing, so that's what this script does.

```bash
automation/lab-healthcheck.sh            # read-only, ~1-2 minutes
automation/lab-healthcheck.sh --attack   # plus the brute-force replay, ~1 more minute
```

Prints one `PASS`/`FAIL` line per check and a summary. The exit code is `0` only if everything
passed, so it also works as a gate in other scripts.

### What it checks

| Area | Checks |
|---|---|
| Proxmox host | all three VMs running and set to autostart in order, guest agents answering, weekly backup job enabled and the newest backup under 8 days old, Fail2ban jails for SSH and the web UI, NAT for the lab network |
| docker01 | key-only SSH and no root login, Fail2ban, UFW default-deny, unused services disabled, unattended-upgrades, the virtio TX-offload and DNS workarounds, all 10 containers running and none unhealthy, indexer `green`, both Wazuh agents active, custom rule ownership, the TheHive integration configured and its daemon running, and an HTTP check on every web service (dashboard, TheHive, Cortex, DVWA, Juice Shop) |
| DC01 | domain, OUs, groups, lab users, `svc-sql` SPN, password policy, the "Audit Policy - Lab" GPO (link, the four registry values, the effective audit policy), the three department shares and their NTFS ACLs, the DHCP scope, DNS records, zone-transfer restriction, the split-horizon policies (and that they didn't break normal resolution), core services, Sysmon and the Wazuh agent configured to forward both event channels (the config, not proof of delivery — `--attack` covers delivery for 4625), and how many days are left on the Windows Server evaluation |
| WS01 | domain join, DNS pointing at DC01, split-horizon answering with the internal IP, SMB to DC01 reachable, the GPO values actually applied, the effective audit policy and that 4688 events are actually being written, no domain users in the local Administrators group, Sysmon and the Wazuh agent |
| `--attack` | sends 10 wrong passwords for `mmustermann` against the domain from DC01, then confirms rule `60122` fired for each one, the frequency rule `60204` fired, and a matching alert really exists in TheHive (queried via its API, not just the integration log) |

### How it works

- Runs from the admin Mac and only uses the SSH aliases that already exist (`pve`, `docker01`).
  Each host gets a single SSH session with all of its checks batched in, so it doesn't run into
  sshd's `MaxStartups` rate limit.
- The Windows checks run through the **QEMU guest agent** (`qm guest exec` on the Proxmox host),
  not RDP/WinRM and not keyboard automation. The PowerShell is sent as `-EncodedCommand`, which
  avoids having to quote it correctly through three layers of shells. It runs as `SYSTEM`, so
  anything that needs a real user context (like the "standard user gets denied" test from
  [ad-lab/04](../ad-lab/04-client-join-least-privilege.md)) is out of scope; the script checks the
  group membership that makes that test pass instead.
- No secrets are stored in the script. The indexer password and the TheHive API key are read on
  docker01 at runtime from the files that already hold them.
- Requires `jq` on the Mac (macOS ships `/usr/bin/jq`).

### Why this matters for SOC work

Detection only works while the whole pipeline (endpoint audit policy → event channel → agent →
manager rule → integration → case-management tool) is intact, and every link in that chain can
break silently. A check like this is the lab-sized version of the detection-health monitoring real
SOCs run, which asks "would we still see it?" rather than "is the service up?".
