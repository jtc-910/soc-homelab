# Hardware migration: MacBook/UTM (ARM64) → bare-metal Proxmox VE (x86_64)

The lab started on a MacBook Pro (M1 Pro, 16 GB RAM) under UTM, with every VM running as an
emulated/native ARM64 guest — including Windows Server 2025 as an unofficial Insider build pulled
from a community mirror, since Microsoft doesn't offer a regular ARM Server download. That worked,
but it hit a real ceiling: Wazuh manager + indexer + dashboard, TheHive/Cortex/Cassandra/
Elasticsearch, and the DVWA/Juice Shop targets on one VM pushed free memory into double-digit MiB,
with DVWA itself stuck in an OOM crash loop (see the historical note in
[04-thehive-cortex.md](04-thehive-cortex.md)). An Intel i9 desktop (32 GB RAM, multiple SSDs) took
over: Proxmox VE installed bare metal, every VM rebuilt from official x86_64 ISOs on an isolated,
NAT'd network segment. Full planning document, including the architecture decisions and phased
sequencing referenced throughout this page:
[migration/proxmox-migration-plan.md](../migration/proxmox-migration-plan.md).

## Why Proxmox, and why rebuild instead of migrate

**Proxmox VE over "Ubuntu Server + KVM":** these are two alternatives for the same box, not layers —
Proxmox is a Debian-based host OS that takes over the machine, not a VM running on top of Ubuntu.
Chosen for live snapshots (used constantly below as rollback points), a web console that needs no
client setup on a headless box, built-in `vzdump`, and LXC/PCIe-passthrough headroom for later
personal-infrastructure projects. `docker01` is a full VM, not an LXC container — Docker-in-LXC needs
nesting/keyctl workarounds that aren't the interesting kind of complexity for this lab.

**Rebuild, not migrate:** ARM64 disk images carry ARM kernels and userland — they don't run on
x86_64, full stop. So every VM was reinstalled from official ISOs rather than converted. That's the
actual win here, not a workaround: the unofficial ARM Insider build (Windows Server's only real
supply-chain smell in this lab) is gone, replaced by the official evaluation ISO.

**What did carry over, deliberately:** the things that live *inside* the VMs, not the VMs
themselves — Docker named volumes (Wazuh indexer/dashboard state, Cassandra), the redacted
Compose files now committed under [configs/](configs/), the custom Wazuh rules/decoders, and the
`custom-w2thive` TheHive integration script. Windows itself (AD database, GPOs, users) was rebuilt
from the provisioning scripts in [ad-lab/scripts/](../ad-lab/scripts/), which is a better artifact
than a restored AD database anyway — it's the reproducible blueprint, not a frozen snapshot.

## The extraction risk that turned out smaller than expected

Before touching any hardware, the repo held **zero** working configuration — no compose files, no
`.env`, no rule XML, all of it living only on the old VM's disk. The migration plan treated this as
the single biggest risk (Phase A wasn't "done" until it was redacted and committed). In hindsight,
that risk was overstated in one specific way: the Wazuh custom rules and decoders extracted from the
old manager (now in [configs/wazuh-manager/](configs/wazuh-manager/)) turned out to be the
**stock Wazuh templates**, not actual lab-specific detections — there was nothing there to lose.
Worth stating plainly rather than letting the original risk assessment stand uncorrected.

## The three real stolen-afternoon bugs

### 1. virtio driver injection silently doesn't fire for Windows Server 2025

`autounattend.xml`'s `DriverPaths` block is supposed to load the virtio-scsi/virtio-net drivers
during Windows Setup, so the install can use `virtio-scsi-pci` (`--scsi0`) instead of the slower
emulated SATA. It didn't work — Setup's WinPE shell (`X:\windows\setupact.log`, reached via
`qm sendkey <vmid> shift-f10` for a `cmd.exe`) confirmed the answer file was found and marked
"usable for pass [windowsPE]", but the PnP/driver-injection step was never evaluated at all (zero
hits for `pnp`/`vioscsi` in the log). Setup then silently fell back to the manual wizard with an
empty disk list. The driver itself wasn't the problem — `drvload e:\vioscsi\2k25\amd64\vioscsi.inf`
from that same WinPE shell loaded it manually without complaint, and the disk appeared right after
in `wmic diskdrive`. It's specifically the automatic injection path that's broken. Not debugged
further, since SATA + `e1000` work natively with zero driver injection and performance is
irrelevant for a lab — `create-vms.sh` creates DC01/WS01 with `--sata0`/`--net0 e1000` for exactly
this reason.

### 2. The `specialize` pass never runs — and there's a second bug hiding behind it

`autounattend-dc01.xml`/`-ws01.xml` copy the provisioning scripts onto the disk during the
`specialize` pass (`mkdir C:\Provision` + `xcopy … "%~dp0scripts" C:\Provision\`), so
`FirstLogonCommands` in `oobeSystem` can run them without depending on the ISO drive letter. The
`oobeSystem` pass (autologon, local admin) demonstrably ran — but `specialize` never did:
`C:\Provision` simply didn't exist on either VM, confirmed with `dir` in a live PowerShell session.
Not yet root-caused (a next step would be grepping `C:\Windows\Panther\setupact.log` for
"specialize" to see if the pass was even evaluated). There's also a **second, independent** bug
hiding behind the first: `%~dp0` is a batch-file token, and it doesn't reliably resolve inside an
inline `cmd /c "..."` call the way it would in a real `.bat` file — so fixing bug #1 alone would
likely still leave `C:\Provision` empty on the `xcopy` step. Worked around on both VMs by manually
finding the ISO drive by volume label (`Get-Volume` → label `AUTOUNATTEND`) and copying the scripts
by hand before running `setup-dc01.ps1`/`setup-ws01.ps1`. Left open, documented in
[99-troubleshooting.md](../99-troubleshooting.md); the clean fix is moving the copy logic into
`FirstLogonCommands` itself (proven to run) instead of through `specialize`.

### 3. virtio-net TX checksum offload corrupts UDP behind the NAT bridge

`docker01` intermittently failed `apt`/`docker pull` with no obvious pattern — just enough dropped
UDP (DNS in particular) to make provisioning flaky. Cause: virtio-net's TX checksum offload doesn't
compute UDP checksums correctly across Proxmox's NAT/masquerade path on the isolated `vmbr1`
segment; the kernel trusts the wrong checksum and the packet gets dropped downstream. Fixed with a
persistent systemd unit (`ethtool -K eth0 tx off` doesn't survive a reboot on its own) — see
[proxmox/docker01-network-fixes.md](../proxmox/docker01-network-fixes.md) for the full unit file,
now baked into `cloud-init-docker01.yaml` so a fresh `docker01` gets it on first boot without a
manual step. A second, unrelated DNS flakiness source (`systemd-resolved`'s stub listener hanging)
is documented in the same file.

## The bug found after declaring the migration done — plus two things that only looked like bugs

Phase E's brute-force replay had already passed once, on paper: 6 failed logons against
`mmustermann` all showed up as Wazuh alerts (`rule.id 60122`, level 5). But the actual migration
plan gate was stricter than that — **alert reaching TheHive**, end to end (not a *case*: promoting
an alert to a case is a manual analyst step in TheHive, and the integration's service account only
holds `manageAlert/create` permission by design) — and re-checking it during this Phase F pass
surfaced two things the first pass missed entirely:

- **The `<integration>` block referencing `custom-w2thive` was completely absent** from the
  restored manager's `ossec.conf` (0 matches). The integration *scripts* had been restored correctly
  from the `wazuh_etc` volume tarball — but the config block that tells Wazuh to actually invoke them
  hadn't made it across, and `wazuh-integratord` wasn't even running as a result. `restore-stacks.sh`
  had assumed the volume restore would carry this; it evidently didn't, at least not reliably enough
  to trust silently — the script now verifies explicitly and prints a loud warning if it's missing.
- **A false lead that cost real debugging time:** checking `thehive4py` against the container's
  default `python3` said the module didn't exist, which looked like a second bug. It wasn't — that's
  the wrong interpreter. `custom-w2thive.py`'s shebang points at Wazuh's own bundled Python
  (`/var/ossec/framework/python/bin/python3`), and `thehive4py` **was** installed there all along
  (version `2.1.0`, from some earlier session — notably not a version PyPI even offers, its releases
  stop at `2.0.3`, so it must have come from a non-PyPI source that wasn't recorded anywhere). Worth
  keeping as a documented trap: on a Wazuh manager, always check the framework interpreter a script's
  shebang actually names, not whatever `python3` resolves to in a shell. One unintended consequence
  of chasing this lead: a `pip install thehive4py==2.0.3` aimed at "fixing" the false problem
  downgraded the already-working `2.1.0` — confirmed harmless (`2.0.3` imports and runs the
  integration correctly), but not something to repeat blindly next time; `thehive4py` lives on no
  volume either way and is lost on every container recreate.
- **A third thing, once the pipe was working, that isn't a bug:** `custom-w2thive.py` deliberately
  skips alerts below rule level 6 — a single failed login (level 5, rule `60122`) is meant to stay
  noise. The *correlation* rule, `60204` ("Multiple Windows Logon Failures", level 10, needs 8
  failures inside 240 seconds from the same source), is what's supposed to reach TheHive. The
  original 6-attempt replay never hit that threshold, so `60204` never fired — it just happened to
  go unnoticed because `60122` alone looked like a pass.

Fixed by re-appending the integration block, pinning `thehive4py` to `2.0.3` (the only concrete
issue found — the stray `2.1.0` isn't on PyPI and its origin is unrecorded, so pinning to a real,
known-good release is the more honest fix regardless of the false lead above), restarting the
manager (`wazuh-control restart` — the integrator daemon only reads `ossec.conf` at startup), and
re-running the replay with 10 attempts instead of 6. Result, this time verified all the way
through: `60204` fired, `custom-w2thive` picked it up, and a real alert (`sourceRef` matching the
Wazuh alert ID) landed in TheHive — confirmed both in `integrations.log` and via a direct query
against TheHive's own API, not just "the log looks happy."

## One more, same root cause: volume-restored files can land on the wrong UID

Separately, `local_rules.xml`/`local_decoder.xml` turned out owned by a stray `1000:1000` instead of
`wazuh:wazuh` (UID 999) after the volume restore — same class of problem as the missing integration
block, different mechanism (tarball restore preserves the source's UID/GID literally). Wazuh doesn't
fail loudly here either: `wazuh-analysisd` just logs a permission-denied warning and quietly falls
back to its stock ruleset, so a genuinely custom detection would silently never fire. Today's
`local_rules.xml`/`local_decoder.xml` only hold Wazuh's stock example content, so nothing was
actually lost this time — but the mechanism is the real finding, not today's empty content. Fixed
with `chown wazuh:wazuh` plus a restart; `restore-stacks.sh` now does this automatically. Full
details: [99-troubleshooting.md](../99-troubleshooting.md).

## Verification

| Check | Result |
|---|---|
| Proxmox host | `pve-manager/9.2.11`, `vmbr0`/`vmbr1` + NAT/masquerade, `ip_forward=1` |
| docker01 stack | all containers `Up`, no restart loop; indexer `_cluster/health` → `green` |
| DC01 | `Get-ADDomain` → `lab.local`; `(Get-ADUser -Filter *).Count` → 17; DHCP scope `.100`–`.200` active |
| WS01 | `(Get-ComputerInfo).CsDomain` → `lab.local`; `nslookup lab.local` → `192.168.100.10` |
| Agents | `agent_control -l` → DC01 and WS01 both `Active` |
| **Alert → TheHive** | Brute-force replay (10× failed login, from an admin session on DC01) → rule `60204` (level 10) → `custom-w2thive` → alert confirmed via TheHive's own API |

Snapshots (`phase-f-verified`) taken on all three VMs after the verification checks above, on top of
the `phase-e-complete` snapshots from the initial rebuild. **Caveat:** these snapshots predate the
rules/decoders ownership fix below — rolling back to `phase-f-verified` brings the permission bug
back with it; re-apply the `chown` from `restore-stacks.sh` after any rollback.

## What this means for the SOC-analyst angle

A snapshot before every risky change turned "did I just break the domain" from a stressful question
into a five-second rollback — that's most of what changed in how confidently I could poke at things
during this pass. An isolated, NAT'd segment with no physical uplink means the eventual Kali/attack
work happens with a real blast-radius boundary, not "hope the firewall rules are right." And the
biggest lesson wasn't really the individual bugs — it was that a green checkmark from an earlier
session (six alerts landed, ship it) had actually only tested one link of a chain that had four,
and the chain-breaking bugs were invisible until something forced re-verifying the *last* link
specifically, not just the first one that happened to be convenient to check.
