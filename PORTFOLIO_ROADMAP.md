# Homelab Portfolio Roadmap — SOC Analyst & Sysadmin

This is my growing list of hands-on projects for this lab. The idea is to build up a wide range of
sysadmin, identity, cloud, and blue-team skills step by step, and write up each one properly in this
repo.

What I want at the end: someone looking at this repo for a minute should be able to tell that I built
a working lab environment myself, that I can think both like an admin and like a defender, and that I
can document what I did clearly.

Status markers: **(done)** means it's finished and linked below, **(partly done)** means some of it
is done, everything else is still open. I added these markers after the fact to track progress — the
rest of this document is the original plan.

---

## How to read this

- The phases roughly follow the order I'm studying for my certifications, so I build portfolio
  proof around the same time I'm learning the material anyway.
- Nothing here is mandatory. It's more of a menu than a checklist — I pick what interests me, because
  the write-ups turn out better when I actually care about the topic.
- Each project lists: what I want to achieve, what skills it covers, what the deliverable is, why it
  matters for SOC work, and roughly how much effort it takes.
- Effort: small (an evening or two), medium (about a week), large (several weeks / a capstone
  project).

---

## Skill overview — what this repo should prove overall

| Area | Concrete skills |
|---|---|
| Sysadmin / on-prem | AD DS, DNS, DHCP, group policies, file shares, printers, WSUS/patching |
| Identity (IAM) | users/groups, role-based access, least privilege, password policies, conditional access, MFA, PIM |
| Cloud | Entra ID, Microsoft 365 tenant, Intune/endpoint management, hybrid identity |
| SIEM / detection | Wazuh, Splunk, Sentinel, log forwarding, detection rules, dashboards |
| Blue team / incident response | simulating attacks, reading event logs, incident write-ups, MITRE ATT&CK mapping |
| Networking | subnetting, basic VLANs, firewall rules, pfSense/OPNsense |
| Hardening / compliance | CIS benchmarks, baseline hardening, audit documentation |
| Linux servers | SSH hardening, Fail2ban, auditd, file integrity monitoring, sudoers, privilege escalation |
| Automation / scripting | PowerShell, Bash, simple automation |
| Documentation | Markdown, network diagrams, writing a good README, version control |

---

## Phase 0 — Foundation (now, alongside the Google certificate)

Goal of this phase: the lab exists, the repo is alive, and the first write-up is online.

### 0.1 — Set up the repo and README (small) — done
- **Goal:** a clean repo structure, a README that actually explains the lab, with a network diagram.
- **Skills:** documentation, Markdown, basic Git (commit, push).
- **Deliverable:** `README.md`, a folder structure, and a first network diagram (draw.io / Excalidraw).
- **Why it matters for SOC work:** knowing your asset inventory and network layout is a basic SOC
  skill.
- **Status:** README is in place, with a real network diagram in
  [`assets/diagrams/network-diagram.svg`](assets/diagrams/network-diagram.svg) (plus an editable
  `.drawio` source file).

### 0.2 — Document the virtualization setup (small) — done
- **Goal:** write down the VM software, VM specs, and the internal lab network (host-only / internal
  network).
- **Skills:** virtualization, network isolation, planning resources.
- **Deliverable:** `00-lab-setup.md` with a VM list, RAM/disk sizes, and the network layout.
- **Why it matters for SOC work:** isolated analysis environments are the same idea as a malware
  sandbox.
- **Status:** [`00-lab-setup.md`](00-lab-setup.md) — I used UTM instead of VirtualBox, same purpose.

### 0.3 — PowerShell basics (small, moved earlier)
- **Goal:** get comfortable with PowerShell basics before building AD: variables, cmdlets, pipelines,
  simple loops and if-statements.
- **Skills:** PowerShell fundamentals — this is the foundation for 1.2 (`New-ADUser`) and every later
  automation project (5.2).
- **Deliverable:** no separate write-up needed, this is just preparation; the first real lines of
  PowerShell go straight into `ad-lab/02-users-and-groups.md`.
- **Why it matters for SOC work:** the most useful everyday skill for both admin and SOC roles. I'd
  originally only planned to pick this up naturally while studying SC-200/Sentinel, but it's worth
  doing earlier.

---

## Phase 1 — Active Directory and on-prem sysadmin work (alongside Google cert to Splunk Fundamentals)

This is the core of my sysadmin credibility.

Principle: I'm doing this phase deliberately *before* Phase 2 (simulating attacks). Build the admin
side first — OUs, group policies, shares — and only attack it afterwards. That way I get both
perspectives from the same environment, and the write-ups prove admin skills in addition to attack
analysis.

### 1.1 — Set up the domain (medium) — done
- **Goal:** Windows Server as a domain controller, a domain, DNS and DHCP configured.
- **Skills:** AD DS, DNS, DHCP, domain architecture.
- **Deliverable:** `ad-lab/01-domain-setup.md` with screenshots of the working domain.
- **Why it matters for SOC work:** Active Directory is the number one attack surface in most
  companies — I need to understand it from the inside.
- **Status:** [`ad-lab/01-domain-setup.md`](ad-lab/01-domain-setup.md) — Windows Server 2025 (ARM),
  domain `lab.local`, DNS is running, DHCP isn't (I'm using fixed IPs in the lab instead).

### 1.2 — Users, groups, and OUs (small) — done
- **Goal:** a realistic org structure: OUs for departments, security groups, 10-15 test users created
  through PowerShell.
- **Skills:** identity basics, OU design, PowerShell (`New-ADUser` in a loop).
- **Deliverable:** `ad-lab/02-users-and-groups.md` plus the PowerShell script itself, in the repo.
- **Why it matters for SOC work:** understanding group membership is central to spotting privilege
  escalation.
- **Status:** [`ad-lab/02-users-and-groups.md`](ad-lab/02-users-and-groups.md) — the four OUs, three
  department groups (IT, Sales, Finance), and 12 test users created via
  [`ad-lab/scripts/create-users.ps1`](ad-lab/scripts/create-users.ps1).

### 1.3 — Group policies: hardening and settings (medium) — partly done
- **Goal:** several group policies: block USB storage, a password policy, force a screen lock,
  turn on PowerShell logging.
- **Skills:** Group Policy, endpoint hardening, logging configuration.
- **Deliverable:** `ad-lab/03-gpo-hardening.md` — for each policy, what it does, how it's configured,
  and how I tested it.
- **Why it matters for SOC work:** the PowerShell logging policy directly feeds detection — I'd be
  generating the exact logs I later hunt through.
- **Status:** [`ad-lab/03-gpo-hardening.md`](ad-lab/03-gpo-hardening.md) — the audit-logging GPO is
  done and verified (logon, account management, and process creation with command-line logging, with
  a real 4688 event confirmed in Wazuh). USB blocking, the password policy, and the other settings
  are still open.

### 1.4 — Client join and least privilege (small) — done
- **Goal:** join a Windows 11 client to the domain, and set up a standard user account without local
  admin rights.
- **Skills:** domain join, the least-privilege principle.
- **Deliverable:** `ad-lab/04-client-join-least-privilege.md`.
- **Why it matters for SOC work:** least privilege is one of the most important preventive controls
  there is.
- **Status:** [`ad-lab/04-client-join-least-privilege.md`](ad-lab/04-client-join-least-privilege.md)
  — domain join done, and confirmed that domain test users are not local admins on WS01 (checked
  `Administrators` group membership, then confirmed a standard user actually gets denied when trying
  something that needs admin rights).

### 1.5 — File server and NTFS permissions (medium) — done
- **Goal:** shared folders with layered permissions (one folder per department), and understanding
  share permissions versus NTFS permissions.
- **Skills:** file servers, access control lists, permission inheritance.
- **Deliverable:** `ad-lab/05-fileserver-acls.md`.
- **Why it matters for SOC work:** data theft and ransomware both target shared folders — understanding
  the permission logic is a must.
- **Status:** [`ad-lab/05-fileserver-acls.md`](ad-lab/05-fileserver-acls.md) — three department shares
  on DC01, wide-open share permissions with NTFS doing the actual restricting, tested and confirmed
  with a real user (`abauer` gets into `IT`, denied from `Finance`).

### 1.6 — Patch management (WSUS, optional) (large) — skipped
- **Goal:** set up the WSUS role, or at least document a patching strategy.
- **Skills:** patch management, the vulnerability lifecycle.
- **Deliverable:** `ad-lab/06-patch-management.md`.
- **Why it matters for SOC work:** unpatched systems are the most common way in — understanding
  patching is the basis of vulnerability management.
- **Status:** skipped on purpose. With only two machines (DC01, WS01), a full WSUS deployment
  wouldn't prove much beyond "I can install a role" — the effort-to-signal ratio is poor here. Could
  revisit later if the lab grows to more endpoints. Ended up covering patch management a different,
  more organic way instead — see 1.6b below.

### 1.6b — Patch management, the real version: updating Wazuh itself (small) — done
- **Goal:** instead of a symbolic WSUS setup, patch a service that's actually running in the lab — a
  real Wazuh update (4.14.6 to 4.14.7) came up while working on the lab, so I used that.
- **Skills:** patch management on a live, multi-component system: backup first, correct upgrade order,
  health checks between steps, post-upgrade verification.
- **Deliverable:** `siem-wazuh/02-patch-management.md`.
- **Why it matters for SOC work:** patch management is about process, not just clicking "update" — a
  SIEM losing agent connections mid-upgrade is its own incident. This proves the process, not just
  that a role can be installed.
- **Status:** [`siem-wazuh/02-patch-management.md`](siem-wazuh/02-patch-management.md) — full VM clone
  as a rollback point (UTM has no live snapshots), indexer backed up, upgraded in the correct order
  (indexer → server → dashboard) with a cluster-health check in between, confirmed both agents still
  connected afterward.

### 1.7 — Basic Linux server hardening and SSH hardening (medium, first Linux step)
- **Goal:** properly harden a lightweight Linux VM (for example, the Wazuh manager): key-based SSH
  login instead of passwords, Fail2ban against brute-force attempts, basic UFW/nftables firewall
  rules, turning off unnecessary services, automatic security updates.
- **Skills:** Linux system administration, SSH hardening, basic firewalling.
- **Deliverable:** `linux-lab/01-ssh-hardening.md` — before and after, including a diff of
  `sshd_config`.
- **Why it matters for SOC work:** SSH is the most common way into an internet-facing Linux server;
  without understanding the hardening basics, I wouldn't be able to make sense of the related alerts
  later.
- **Status:** done — key-based SSH login enforced (password and root login disabled), Fail2ban
  active on the SSH jail (tested by getting my own IP banned and unbanning it again), UFW default-
  deny with only the needed ports open to the lab subnet, unused services (ModemManager,
  multipathd, udisks2) turned off, and automatic security updates confirmed working via a dry run.
  See [`linux-lab/01-ssh-hardening.md`](linux-lab/01-ssh-hardening.md).

### 1.8 — Set up DHCP on DC01 (small, doubles as Network+ practice)
- **Goal:** add the DHCP role to DC01, create a scope for the lab network, and set reservations for
  DC01, WS01, and the Wazuh box instead of the fixed IPs I've been using by hand.
- **Skills:** DHCP scopes, reservations, leases — a core Network+ topic (DNS/DHCP domain).
- **Deliverable:** `ad-lab/07-dhcp.md`.
- **Why it matters for SOC work:** DHCP logs are a common source for tying an IP address back to a
  device at a point in time during an investigation.
- **Status:** done. See [`ad-lab/07-dhcp.md`](ad-lab/07-dhcp.md) — DC01, WS01, and the Wazuh box
  deliberately kept on their existing fixed IPs; the DHCP scope (192.168.100.100–200) is for future
  transient clients instead.

### 1.9 — A deliberate network troubleshooting exercise (small, Network+ practice)
- **Goal:** break something on purpose (wrong subnet mask, wrong default gateway, DNS pointed at the
  wrong server) and then diagnose and fix it using a proper troubleshooting method instead of
  guessing, and write it up as a before/after.
- **Skills:** structured network troubleshooting — this is close to the Network+ troubleshooting
  methodology, so it doubles as exam practice.
- **Deliverable:** `ad-lab/08-network-troubleshooting.md`.
- **Why it matters for SOC work:** a lot of "is this an attack or just broken config" triage starts
  with the same systematic troubleshooting instinct.
- **Status:** postponed. I already have real troubleshooting stories in `99-troubleshooting.md` —
  this would be a deliberately staged one, written up the same honest way. Decided to hold off until
  there's a dedicated network segment to break things in (see Phase 3), rather than staging a fault
  on WS01 while it's still doing double duty as the main domain-joined client.

### 1.10 — DNS beyond the basics (small)
- **Goal:** go past "DNS resolves names" into record types, zone transfers (and why they should be
  restricted), and split-horizon DNS.
- **Skills:** DNS internals — another core Network+ topic, and a natural follow-up to the DNS cleanup
  I already did (see `99-troubleshooting.md`).
- **Deliverable:** `ad-lab/09-dns-deep-dive.md`.
- **Why it matters for SOC work:** DNS is one of the most abused protocols for both C2 and
  exfiltration — understanding it properly, not just "it resolves names", matters for detection.
- **Status:** mostly done. See [`ad-lab/09-dns-deep-dive.md`](ad-lab/09-dns-deep-dive.md) — record
  types (CNAME/MX/TXT), zone transfer restriction verified, split-horizon DNS built with DNS
  Policies and zone scopes and verified from the internal side. The external side of split-horizon
  still needs a client outside the lab subnet to test against — planned once the Kali VM (Phase 2)
  exists.

### 1.11 — Windows Firewall rules as an ACL warm-up (small)
- **Goal:** use the Windows Defender Firewall on DC01/WS01 to write ACL-style rules (block specific
  traffic, then test that it's actually blocked) — a lightweight preview of firewall logic before
  building a dedicated firewall VM in Phase 3.
- **Skills:** basic firewall rule logic, testing that a rule actually does what I think it does.
- **Deliverable:** `ad-lab/10-windows-firewall-acls.md`.
- **Why it matters for SOC work:** reading and reasoning about firewall rules is a building block for
  the real pfSense work later (3.1) and for understanding firewall logs in general.
- **Status:** mostly done. See [`ad-lab/10-windows-firewall-acls.md`](ad-lab/10-windows-firewall-acls.md)
  — ICMP allow/block and rule-precedence tested (plus an unplanned but useful default-deny
  discovery). The SMB-blocking half is still open — ran into a permissions snag testing it as a
  non-admin account and paused rather than rushing it.

### 1.12 — Wireshark and tcpdump traffic analysis, pulled forward (small)
- **Goal:** same as roadmap item 3.3 below — capture and analyze traffic (a plaintext login, a port
  scan) — but done now instead of waiting for Phase 3, since it only captures existing traffic and
  doesn't require changing the network. Small lab, small analysis: capture on the Wazuh Linux box
  with `tcpdump` first (the tool that's actually available on a server with no GUI), save it to a
  `.pcap`, then open the same capture in Wireshark on my Mac for the deeper visual analysis.
- **Skills:** packet analysis, protocol understanding, command-line vs. GUI capture tools — a core
  Network+ topic.
- **Deliverable:** `network/03-wireshark-analysis.md` (same deliverable as 3.3 — doing this early just
  means 3.3 is already done by the time Phase 3 starts).
- **Why it matters for SOC work:** packet-capture analysis is a Tier-1/Tier-2 skill for
  network-related alerts, and `tcpdump` is often the only capture tool available on a real
  (headless) server — knowing both matters more than knowing just the GUI tool.
- **Status:** unblocked — Wazuh now runs as a Docker container on `docker01` (2b.2 done), so this can
  capture and analyze the post-migration setup rather than doing it twice. Not started yet.

---

## Phase 2 — SIEM and detection engineering (alongside TryHackMe SAL1 / Splunk)

This is where the repo shifts from a pure sysadmin profile toward a blue-team one.

### 2.1 — Set up Wazuh and roll out agents (medium) — done
- **Goal:** a Wazuh manager (on a Linux VM) plus agents on the server and the client.
- **Skills:** SIEM deployment, log forwarding, agent management.
- **Deliverable:** `siem-wazuh/01-wazuh-deployment.md` plus an architecture diagram.
- **Why it matters for SOC work:** this is the tool a Tier-1 analyst lives in every day — having set
  it up myself is a strong signal.
- **Status:** [`siem-wazuh/01-wazuh-deployment.md`](siem-wazuh/01-wazuh-deployment.md) — manager on
  Ubuntu, both agents (DC01, WS01) active.

### 2.2 — Failed-login detection (brute force) (medium) — done
- **Goal:** simulate a brute-force attempt against a domain user, see Windows event 4625 show up in
  Wazuh, and build an alert around it.
- **Skills:** detection rules, event log analysis, simulating an attack.
- **Deliverable:** `incident-writeups/01-bruteforce.md` with a MITRE ATT&CK mapping (T1110).
- **Why it matters for SOC work:** this is the single most classic Tier-1 alert scenario there is.
- **Status:** [`incident-writeups/01-bruteforce.md`](incident-writeups/01-bruteforce.md) — including
  the account lockout as a bonus observation.

### 2.3 — Detect a suspicious AD change (medium)
- **Goal:** create a new admin user through a script, add it to "Domain Admins", and catch that as an
  alert.
- **Skills:** privilege-escalation detection, AD auditing.
- **Deliverable:** `incident-writeups/02-rogue-admin.md` (MITRE T1098 / T1078).
- **Why it matters for SOC work:** persistence and privilege escalation are core detection use cases.
- **Status:** open.

### 2.4 — Splunk in parallel: same data, different tool (medium)
- **Goal:** bring the same logs into Splunk Free, run some basic SPL searches, build a simple
  dashboard.
- **Skills:** Splunk SPL, dashboards, comparing tools.
- **Deliverable:** `siem-splunk/01-splunk-vs-wazuh.md` — a comparison of the two SIEMs.
- **Why it matters for SOC work:** knowing more than one SIEM is a real differentiator in the DACH job
  market.
- **Status:** open.

### 2.5 — Roll out Sysmon and improve detection (medium) — done
- **Goal:** install Sysmon with a curated config (for example, SwiftOnSecurity's) on the clients, for
  much richer telemetry.
- **Skills:** endpoint telemetry, process monitoring, tuning a config.
- **Deliverable:** `siem-wazuh/02-sysmon.md`.
- **Why it matters for SOC work:** Sysmon event IDs (1, 3, 11, 22, and so on) are detection
  bread-and-butter.
- **Status:** done, but currently written up as a section inside
  [`siem-wazuh/01-wazuh-deployment.md`](siem-wazuh/01-wazuh-deployment.md) rather than its own file.

### 2.6 — Detection dashboard / SOC overview screen (medium) — partly done
- **Goal:** a clear dashboard: top alerts, failed logins, agent status.
- **Skills:** visualization, thinking in KPIs, dashboard design.
- **Deliverable:** `siem-wazuh/03-dashboard.md` with screenshots.
- **Why it matters for SOC work:** Tier-1 analysts spend their day looking at dashboards.
- **Status:** I have an overview screenshot (in [`04-validation.md`](04-validation.md)), but no
  dedicated dashboard write-up yet.

### 2.7 — SSH brute-force detection (medium, builds on 1.7)
- **Goal:** attack my own hardened Linux VM from 1.7 with a brute-force tool (Hydra or similar), and
  see the Fail2ban bans and auth-log events show up as an alert in Wazuh — the Linux equivalent of
  2.2.
- **Skills:** Linux log analysis (`/var/log/auth.log`), detection rules, simulating an attack.
- **Deliverable:** `incident-writeups/03-ssh-bruteforce.md` with a MITRE mapping (T1110), including a
  comparison to the Windows version.
- **Why it matters for SOC work:** shows I can do brute-force detection across platforms, not just in
  the Windows world.
- **Status:** open (needs 1.7 first).

### 2.8 — auditd and file integrity monitoring (medium, Linux)
- **Goal:** set auditd rules for sensitive paths and commands (`/etc/shadow`, `sudo` calls) and feed
  them through the Wazuh agent; also turn on file integrity monitoring (Wazuh's own module, or AIDE)
  on sensitive directories, change a file, and check that it alerts.
- **Skills:** Linux auditing, file integrity monitoring, log pipeline configuration.
- **Deliverable:** `siem-wazuh/04-linux-auditd-fim.md`.
- **Why it matters for SOC work:** Linux host telemetry is the counterpart to the Sysmon work in 2.5 —
  together they show endpoint detection skills across both platforms.
- **Status:** open.

---

## Phase 2b — Docker, case management, and Zero-Trust access (added 12.08.2026)

This phase came out of thinking through what's actually missing from the portfolio so far: detection
(Wazuh) without response (a case-management tool) only tells half the SOC story, and everything here
is planned to run in Docker — a second platform alongside the existing UTM VMs, not a replacement for
them. DC01 and WS01 stay full VMs on purpose: a domain controller and an endpoint I do threat hunting
on need real OS behavior, not a container.

### 2b.1 — Docker as a second platform alongside UTM (small)
- **Goal:** get Docker running as the platform for everything else in this phase. Containers make
  sense for the tooling that follows (Wazuh, TheHive, DVWA/Juice Shop, and later candidates like
  Suricata or MISP all ship official Docker images) — but not for DC01 or WS01, which stay full VMs.
- **Host decision:** Docker runs directly on the existing Wazuh VM (`192.168.100.30`) rather than a
  new dedicated VM — no extra RAM overhead for a whole separate machine, and it's where Wazuh itself
  ends up living post-migration (2b.2) anyway. Every container from this phase (DVWA/Juice Shop,
  TheHive/Cortex, the Twingate connector, and later candidates) runs on this same box.
- **Skills:** Docker basics, Docker Compose, judging what belongs in a container versus a full VM.
- **Deliverable:** `docker-lab/01-docker-intro.md`.
- **Why it matters for SOC work:** most modern security tooling ships as containers — knowing when
  to containerize something and when not to is itself part of the skill, not just running
  `docker-compose up`.
- **Status:** done. See [`docker-lab/01-docker-intro.md`](docker-lab/01-docker-intro.md) — the
  former "wazuh" VM is now `docker01` (same IP, `192.168.100.30`), Docker Engine and Compose
  installed and verified.

### 2b.2 — Migrate Wazuh from a VM to Docker (large, high value)
- **Goal:** migrate the existing Wazuh Ubuntu VM (192.168.100.30) to Docker containers, rather than
  standing up a fresh instance — back up the config, custom rules, and data first, write an actual
  cutover plan and a rollback plan, then do the migration for real.
- **Skills:** service migration without data loss, Docker volumes versus VM-disk persistence, backup
  and rollback planning under real constraints (this is a service I actually rely on, not a
  throwaway lab VM).
- **Deliverable:** `docker-lab/02-wazuh-migration.md`.
- **Why it matters for SOC work:** migrating a live service without losing data or downtime is a real
  sysadmin skill, and doing it to my own working SIEM instead of a disposable test instance raises
  the stakes in a way that shows up in the write-up.
- **Status:** done. See [`docker-lab/02-wazuh-migration.md`](docker-lab/02-wazuh-migration.md) —
  manager, indexer, and dashboard now run as containers on `docker01`; both agents (DC01, WS01)
  reconnected using their original `client.keys` with no re-enrollment; native services disabled
  (not removed) as a rollback path. Old indexer event history was deliberately not migrated (a
  documented trade-off, not an oversight).

### 2b.3 — DVWA and Juice Shop as Docker attack targets (small)
- **Goal:** stand up DVWA and OWASP Juice Shop fresh in Docker (no migration, no prior instance) as
  deliberately vulnerable targets for the planned WAF project (nginx + ModSecurity/OWASP CRS, or
  pfSense as a WAF layer).
- **Skills:** Docker Compose for multi-container setups, working with intentionally vulnerable apps
  safely (isolated network segment only).
- **Deliverable:** `docker-lab/03-dvwa-juiceshop.md`.
- **Why it matters for SOC work:** gives Wazuh (and later Suricata) something realistic to detect
  against, and sets up the future WAF project without needing a real, risky vulnerable target.
- **Status:** done. See [`docker-lab/03-dvwa-juiceshop.md`](docker-lab/03-dvwa-juiceshop.md) — both
  running on `docker01` in their own isolated Docker network, separate from the Wazuh stack. DVWA
  needed `binfmt`/QEMU emulation set up first (amd64-only image on an ARM64 host).

### 2b.4 — TheHive and Cortex: closing the detection-to-response gap (medium-large, highest priority)
- **Goal:** stand up TheHive (incident-response case management) and Cortex (analysis/enrichment
  engine) in Docker, and wire Wazuh alerts into TheHive so they become actual cases instead of
  disappearing into a dashboard once viewed.
- **Skills:** case-management workflows, alert-to-case pipelines, SOAR-adjacent tooling.
- **Deliverable:** `docker-lab/04-thehive-cortex.md`.
- **Why it matters for SOC work:** Wazuh shows I can detect an alert; this shows I can work one —
  triage, document, escalate — which is the actual Tier-1 job, not just watching a dashboard light
  up.
- **Status:** open — the single highest-priority next step in the whole roadmap right now.

### 2b.5 — Twingate: Zero-Trust remote access (small-medium)
- **Goal:** set up Twingate as a Zero-Trust remote-access overlay into the lab network instead of a
  classic VPN — no port forwarding required. The free tier (5 users, 10 remote networks, permanently
  free) is enough for a solo lab. The connector runs as a lightweight container/VM inside
  `lab.local`.
- **Skills:** Zero-Trust access-control concepts, a practical modern alternative to VPN.
- **Deliverable:** `docker-lab/05-twingate.md`.
- **Why it matters for SOC work:** Zero-Trust access is directly relevant to SC-200/Security+
  material, and it also makes the lab itself genuinely reachable from outside going forward.
- **Status:** open.

### 2b.6 — Patch/update automation, picked up along the way (small, no dedicated time slot)
- **Goal:** light automation for keeping the existing lab patched — DC01, WS01, Wazuh, and whatever's
  now running in Docker. Deliberately not a dedicated Ansible learning track; more an organic
  byproduct of doing the work, the same way Bash came from the TryHackMe/Wazuh material and
  PowerShell came from SC-200/Sentinel.
- **Skills:** whatever automation/scripting approach turns out to be the practical choice, picked up
  incidentally rather than studied on its own.
- **Deliverable:** folded into whichever `docker-lab/` page it naturally comes up in, rather than a
  dedicated page of its own.
- **Why it matters for SOC work:** shows automation as a practical habit that grows out of real
  maintenance work, not a checkbox skill studied in isolation.
- **Status:** open, ongoing, no fixed slot in the roadmap.

### Explicitly out of scope for now: Kubernetes
No Kubernetes work is planned as part of this phase or this repo for the time being — Docker Compose
covers everything here. Possibly a "year 2" idea alongside an eventual OSCP path, but not scoped or
scheduled.

### Further Docker candidates (later, no fixed timing)
A few more services came up as ideas while thinking this through — not scheduled yet, just noted so
they don't get lost:
- **Suricata or Zeek** — network-based IDS, complementing the host-based Wazuh detection already in
  place. Possibly the Docker-based way to do roadmap item 3.4 instead of a dedicated VM — to be
  decided when that item comes up.
- **Portainer** — a Docker GUI, worth adding once several containers are actually running here.
- **OpenVAS/Greenbone** — a vulnerability scanner, useful to run before the planned AD-pentest work
  in Phase 2.
- **MISP** — a threat-intel platform, more relevant once the lab is further into a SIEM-engineer-style
  phase than it is right now.

---

## Phase 3 — Network and perimeter (alongside Security+)

This is where my existing CCNA knowledge shows up in the portfolio.

### 3.1 — pfSense / OPNsense as the lab firewall (medium)
- **Goal:** a firewall VM between lab segments, with rules, logging to the SIEM.
- **Skills:** firewalling, segmentation, rule logic.
- **Deliverable:** `network/01-firewall.md` plus an updated topology diagram.
- **Why it matters for SOC work:** firewall logs are a core SOC data source.
- **Status:** open — deliberately postponed until Phase 1 and 2 are further along, so I'm not
  rebuilding the network in the middle of the AD/SIEM work.

### 3.2 — Network segmentation and VLANs (medium)
- **Goal:** several segments (servers / clients / a "DMZ"), with routing documented.
- **Skills:** subnetting, basic VLAN concepts, the zero-trust idea.
- **Deliverable:** `network/02-segmentation.md`.
- **Why it matters for SOC work:** understanding lateral movement requires understanding network
  topology first.
- **Status:** open.

### 3.3 — Traffic analysis with Wireshark (small)
- **Goal:** capture and analyze suspicious traffic (for example, a plaintext login, or a port scan).
- **Skills:** packet analysis, protocol understanding.
- **Deliverable:** `network/03-wireshark-analysis.md` with annotated screenshots.
- **Why it matters for SOC work:** packet-capture analysis is a Tier-1/Tier-2 skill for
  network-related alerts.
- **Status:** pulled forward to 1.12, since it doesn't need the Phase 3 network rebuild — check there
  first.

### 3.4 — IDS with Suricata or Snort (large)
- **Goal:** set up an IDS, trigger a signature, send the alert into the SIEM.
- **Skills:** IDS/IPS, signature logic, detection pipelines.
- **Deliverable:** `network/04-suricata-ids.md`.
- **Why it matters for SOC work:** network-based detection complements endpoint detection — together
  they give a complete blue-team picture.
- **Status:** open.

---

## Phase 4 — Cloud identity and Microsoft 365 (alongside SC-900 / SC-200)

The layer that rounds out my identity-management profile.

### 4.1 — Entra ID tenant and cloud users (small, can be moved earlier alongside Phase 1)
- **Goal:** a Microsoft 365 developer tenant, cloud users, groups, licenses.
- **Skills:** cloud identity, Entra ID basics.
- **Deliverable:** `cloud-iam/01-entra-setup.md`.
- **Why it matters for SOC work:** cloud identity is where most modern attacks focus.
- **Note:** understanding hybrid AD/Entra setups is standard in DACH companies and covers part of the
  MD-102 material — if I want to move faster toward an IT admin / systems engineer role, I could pull
  this forward instead of waiting for Phase 4.
- **Status:** open.

### 4.1b — Hybrid identity with Entra Connect (medium, high value)
- **Goal:** sync DC01's on-prem AD to the Entra ID tenant from 4.1 with Entra Connect (or Entra
  Connect Sync/Cloud Sync), so the lab becomes a real hybrid identity setup instead of two separate,
  disconnected identity stores — which is what most companies in the DACH market actually run, not
  a clean cloud-only tenant.
- **Skills:** hybrid identity, directory synchronization, understanding what stays on-prem versus
  what moves to the cloud in a hybrid model.
- **Deliverable:** `cloud-iam/01b-hybrid-identity.md`.
- **Why it matters for SOC work:** hybrid sync is where a lot of real-world identity attacks
  actually live (e.g. attacking the sync account, or on-prem AD as the softer path into a hybrid
  tenant) — and it's the setup most SOC analysts in this market will actually see, not a pure-cloud
  environment.
- **Status:** open. Needs 4.1 (Entra tenant) first, and reuses the existing DC01 from Phase 1.

### 4.2 — Conditional Access policies (medium)
- **Goal:** build policies: require MFA, block logins from certain countries, require device
  compliance.
- **Skills:** Conditional Access, risk-based access control.
- **Deliverable:** `cloud-iam/02-conditional-access.md`.
- **Why it matters for SOC work:** Conditional Access is the main preventive cloud control — and a
  source of many sign-in alerts.
- **Status:** open.

### 4.3 — MFA and passwordless sign-in (small)
- **Goal:** configure MFA methods, self-service password reset.
- **Skills:** MFA, credential security.
- **Deliverable:** `cloud-iam/03-mfa.md`.
- **Why it matters for SOC work:** MFA fatigue and MFA bypass are current, common attack patterns.
- **Status:** open.

### 4.4 — Privileged Identity Management (PIM) (medium)
- **Goal:** just-in-time admin access, time-limited roles.
- **Skills:** PIM, privileged access management.
- **Deliverable:** `cloud-iam/04-pim.md`.
- **Why it matters for SOC work:** monitoring privileged access is high-value detection work.
- **Status:** open.

### 4.5 — On-prem AD versus Entra ID — a comparison document (medium, high value)
- **Goal:** a direct comparison: Kerberos versus OAuth/SAML, group policy versus Intune policy, when
  to use which, and hybrid identity.
- **Skills:** architectural understanding, big-picture thinking.
- **Deliverable:** `cloud-iam/05-ad-vs-entra.md`.
- **Why it matters for SOC work:** this is the kind of document that does well in interviews — it
  shows I understand the system, not just individual tools.
- **Status:** open.

### 4.6 — Microsoft Sentinel: the cloud SIEM (large)
- **Goal:** a Sentinel workspace, Entra logs connected, an analytics rule, a KQL query.
- **Skills:** Sentinel, KQL, cloud detection.
- **Deliverable:** `cloud-iam/06-sentinel.md`.
- **Why it matters for SOC work:** the Microsoft stack dominates the DACH market, so this is directly
  relevant.
- **Status:** open.

### 4.7 — Intune / endpoint management (medium)
- **Goal:** enroll a device, set a compliance policy, deploy an app.
- **Skills:** mobile device management, endpoint management (covers MD-102 material).
- **Deliverable:** `cloud-iam/07-intune.md`.
- **Why it matters for SOC work:** device compliance is the gateway into Conditional Access.
- **Status:** open.

### 4.8 — Least privilege IAM architecture, bringing it together (medium, high value)
- **Goal:** one document that ties the on-prem and cloud identity work into a single, coherent least
  privilege architecture instead of leaving it as separate, disconnected pieces: the OU/group
  structure and NTFS ACLs from 1.2/1.5 on the on-prem side, Conditional Access, MFA, and PIM
  (4.2–4.4) on the cloud side. Includes a diagram showing how a user's access is actually
  constrained end to end (group membership → NTFS/share permissions → Conditional Access →
  time-limited privileged roles).
- **Skills:** architectural thinking, IAM design, communicating a security model rather than just a
  list of settings.
- **Deliverable:** `cloud-iam/08-least-privilege-architecture.md` plus a diagram.
- **Why it matters for SOC work:** interviews ask "how would you design least privilege here" far
  more often than "how do you configure PIM" — this document is the answer to the first question,
  built from things I actually did rather than theory.
- **Status:** open. Depends on 1.2/1.5 (done) and 4.2–4.4 (open) being in place first, since it's a
  synthesis of that work rather than a new hands-on step.

---

## Phase 5 — Hardening, compliance, and a capstone project

This is the level of polish that sets a portfolio apart from other candidates.

### 5.1 — CIS benchmark hardening (medium)
- **Goal:** harden a Windows client or server against a CIS benchmark, and document before/after.
- **Skills:** security baselines, compliance, auditing.
- **Deliverable:** `hardening/01-cis-windows.md`.
- **Why it matters for SOC work:** deviations from a baseline are a whole category of alerts on their
  own.
- **Status:** open.

### 5.2 — PowerShell automation (medium)
- **Goal:** one useful script — for example, finding inactive AD users, generating a login report, or
  a lab health check.
- **Skills:** PowerShell, automation, reporting.
- **Deliverable:** `automation/` with the scripts, plus a short README for each one.
- **Why it matters for SOC work:** Tier-1 automation saves time and shows initiative.
- **Status:** open.

### 5.3 — Vulnerability scan with OpenVAS or Nessus (medium)
- **Goal:** scan the lab, prioritize the findings, write a remediation plan.
- **Skills:** vulnerability management, risk prioritization.
- **Deliverable:** `hardening/02-vuln-scan.md`.
- **Why it matters for SOC work:** reading and prioritizing vulnerability-scan reports is Tier-1
  everyday work.
- **Status:** open.

### 5.4 — Sudo misconfiguration and Linux privilege escalation (medium, advanced Linux)
- **Goal:** deliberately introduce an unsafe sudoers rule or an exploitable SUID binary into a target
  VM, then escalate privileges myself using LinPEAS/GTFOBins — both an attacker and a defender
  write-up in one.
- **Skills:** Linux privilege escalation, sudoers logic, understanding SUID and GTFOBins.
- **Deliverable:** `linux-lab/02-privesc-sudoers.md` with a MITRE mapping (T1548).
- **Why it matters for SOC work:** recognizing privilege-escalation paths (not just Kerberoasting on
  Windows) rounds out my detection profile across both operating systems — the Linux equivalent of
  2.3.
- **Status:** open.

### 5.5 — Bash automation (small, closes out the Linux track)
- **Goal:** one or two useful scripts — for example, summarizing failed SSH logins, a lab health
  check, or checking log rotation. The Linux equivalent of 5.2.
- **Skills:** Bash scripting, automation, reporting.
- **Deliverable:** `automation/` (same folder as 5.2) with Bash scripts plus a README for each.
- **Why it matters for SOC work:** Bash is standard on Linux SIEM hosts and in a lot of detection
  pipelines — this rounds out the automation story across platforms.
- **Status:** open.

### 5.6 — Capstone: end-to-end incident simulation (large, high value)
- **Goal:** simulate a full attack chain (initial access, persistence, privilege escalation,
  exfiltration) and trace it all the way through the SIEM.
- **Skills:** everything combined — attacking, detecting, analyzing, and writing an incident report.
- **Deliverable:** `incident-writeups/capstone-full-killchain.md` — a detailed report with a timeline,
  MITRE mapping, and lessons learned.
- **Why it matters for SOC work:** this is the centerpiece. One link that proves the full range of
  skills.
- **Status:** open.

---

## Personal infrastructure ideas (not part of the portfolio, just noted so they don't get lost)

These came up while thinking about Proxmox/LXC and aren't part of this lab or the portfolio — they're
real home-network upgrades for later, once I have a dedicated mini PC. Keeping them here separately so
"portfolio project for job applications" and "my actual home network" don't get mixed together.

- **A mini PC running Proxmox as a bare-metal hypervisor.** Checked this against the current lab:
  Proxmox VE 9.2 does have an official ARM64 ISO now (released 05.08.2026), but it needs an Armv9-A+
  CPU with standard UEFI boot — my M1 Pro doesn't meet that, and Apple Silicon's non-standard boot
  chain means a generic ARM64 server ISO wouldn't just boot on this Mac anyway (this is why the Asahi
  Linux project needed years of custom bootloader work). So this needs actual separate hardware
  (x86 mini PC, most likely), not something to try on the current Mac.
- **Replace my actual home router with pfSense**, running on that same box.
- **Pi-hole** as a network-wide DNS-level ad/tracker blocker, alongside pfSense.
- **A self-hosted NAS/cloud** (e.g. TrueNAS or Nextcloud) for local file storage instead of relying on
  third-party cloud storage.
- **Once the mini PC exists, move the current lab VMs there instead of running them on the Mac.**
  This would also solve a real, current problem: DC01 + WS01 + the Docker/Wazuh box running
  simultaneously on the Mac's RAM is already tight. Dedicated hardware would remove that constraint
  entirely, on top of being closer to how a real homelab is usually run (dedicated hardware, not a
  laptop doing double duty).

---

## Stretch ideas (if I have the time and interest)

- A MITRE ATT&CK coverage map — which techniques my lab can actually detect, shown visually.
- Atomic Red Team — run standardized attack tests automatically and check detection coverage.
- A DFIR exercise — analyze a memory or disk image (Volatility, Autopsy).
- A phishing simulation — a controlled phishing email in the lab, with click detection.
- A honeypot — set up something simple and log the attacks against it.
- Threat-intel enrichment — match IOCs from a feed against my own logs.
- Backup and recovery — simulate a ransomware scenario and document the recovery.
- Documentation as code — make the whole lab reproducible with Ansible or Terraform (quite advanced).

---

## Quality checklist for every write-up

To keep every document interview-ready:

- A clear goal, stated in one sentence
- The environment (which VMs, which tools)
- Steps that someone else could actually follow and reproduce
- Screenshots of the working configuration
- Problems and how I solved them (shows real troubleshooting)
- A MITRE ATT&CK mapping, for detection topics
- Two or three sentences on why it matters for SOC work
- Clean Markdown, no typos

---

## Recommended order, at a glance

```
Phase 0  ->  repo and lab exist
Phase 1  ->  AD / sysadmin work (sysadmin applications become realistic from here)
Phase 2  ->  SIEM plus first incident write-ups (blue-team profile starts to show)
Phase 3  ->  network and perimeter (CCNA knowledge becomes visible)
Phase 4  ->  cloud identity and Sentinel (fits the Microsoft-heavy DACH market)
Phase 5  ->  hardening and the capstone (shows maturity)
```

Rule of thumb: five deep, clean write-ups beat twenty shallow ones. Depth matters more than breadth
for quality — but this roadmap is here to give me breadth to choose from.

---

This roadmap is a living document. I'll check things off, add to it, and adjust it as the repo grows
along with what I can do.
