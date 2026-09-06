# Problems I ran into (and how I fixed them)

> **Note:** most of this page covers the original ARM64/UTM build on a MacBook. That environment
> is gone — the lab now runs on bare-metal Proxmox VE (x86_64), see
> [docker-lab/05-hardware-migration.md](docker-lab/05-hardware-migration.md) — so entries below
> tagged **[ARM/UTM, historical]** no longer apply, but stay here since the debugging process is
> still the point. New problems from the Proxmox/x86_64 environment get their own entries too.

Running this lab on an Apple Silicon Mac meant a lot of small things worked differently than they
would on a normal Intel PC. I'm keeping every problem and fix here — partly so I don't have to
re-solve them, and partly because figuring these out is honestly a big part of the learning.

## Quick things to remember

- The Windows Server ARM image is a preview build, so it behaves a little like beta software. Fine
  for a lab, just note which build you used.
- Network card names differ (Windows calls it "Ethernet", Ubuntu calls it "enp0s1"). Always check
  first with `Get-NetAdapter` or `ip -br a` before setting a fixed IP.
- Install the guest tools in each Windows VM, otherwise the screen resolution is stuck and copy-paste
  doesn't work.
- If joining the domain fails, check DNS first. Almost always the client's DNS isn't pointing at
  DC01.
- Windows 11 has to be Pro to join a domain.
- With 16 GB RAM, don't run every VM at once — shut down what you don't need.

## Domain controller setup failed with error 0x8007000B [ARM/UTM, historical]

When I tried to turn DC01 into a domain controller, `Install-ADDSForest` failed with "An attempt was
made to load a program with an incorrect format" (`0x8007000B`).

The cause was sneaky: Windows on ARM can quietly run programs in a "pretend-Intel" mode, and my
PowerShell window happened to be one of those. So it tried to load ARM parts into an Intel process
and choked. I checked with:

```powershell
$env:PROCESSOR_ARCHITECTURE   # showed AMD64, but the machine is ARM64
```

The fix was to start the real ARM64 PowerShell as Administrator
(`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`), confirm it now said `ARM64`, and run
the command again. It worked immediately. Lesson: on an ARM machine, check which PowerShell you're
actually in before running low-level tools.

## The Windows Server x64 installer wouldn't accept "no product key" [ARM/UTM, historical]

Before switching to the ARM build, I tried the official Intel Server ISO through emulation. Its
installer kept failing with "the product key couldn't be verified", even when I chose "I don't have
a product key". This is a known bug in the new Server 2025 setup inside a VM. Combined with how slow
emulation was, I gave up on the Intel route and used the native ARM build instead.

## Screen resolution was stuck / greyed out

Right after installing Windows, the resolution couldn't be changed. That's just the missing display
driver. Installing the SPICE guest tools and rebooting fixed it, and copy-paste started working too.

## Wazuh install ran out of disk space

The Wazuh installer failed near the end with "No space left on device", even though I'd made a 40 GB
disk. The reason is an Ubuntu default: its installer only uses about half the disk for the system and
leaves the rest unused. I grew the system volume into the free space:

```bash
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
df -h /            # now ~37 GB
```

Then I re-ran the installer. Best to fix this during the Ubuntu install itself (set the volume to max
on the storage screen).

## The big one: getting the machines to talk to each other [ARM/UTM, historical]

This is what took me the longest. On this Mac, the different UTM network modes each only gave me half
of what I needed:

- One mode gave internet but kept every VM on its own private island (they couldn't see each other).
- Another let the VMs see each other but had no internet.

I also learned that a Linux VM created with "Use Apple Virtualization" runs on a completely different
engine than the Windows VMs, and the two engines can't share a private network at all. I tried
several combinations (two network cards per machine, host-only networks, bridging to my home network)
and each one led to a new dead end — including a Windows VM that refused to boot once I added a second
network card.

What finally worked (thanks to a blog post on kilala.nl):

1. Make sure every VM runs on the **same** engine — I rebuilt the Ubuntu VM with "Use Apple
   Virtualization" turned **off** so it matches the Windows VMs (QEMU).
2. On every VM, set the one network card to **Shared Network**, then open the advanced settings and
   type the **same** values into the greyed-out fields on each one:
   - Guest Network `192.168.100.0/24`, DHCP `192.168.100.15` to `.50`

That forces all the machines onto one shared network. The result: they can reach each other, they
have internet, and they're still separated from my home network — with just one network card each,
and no boot problems. The gateway is `192.168.100.15`, and I gave the machines fixed addresses
(DC01 `.10`, WS01 `.20`, wazuh `.30`).

## DNS on the domain controller was timing out

After all the network changes, `nslookup lab.local` on DC01 kept timing out and showed a strange
`fe80::...` address as the DNS server. Two leftovers from the earlier network attempts were to blame:

1. The network card had picked up an IPv6 DNS server (the `fe80::...` one) that didn't answer.
   Windows tried it first every time and waited for it to time out.
2. Old records were still hanging around in DNS — a dead forwarder and some address records pointing
   at IPs from the previous network.

I turned off IPv6 on the card and cleaned up the old records:

```powershell
Disable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 127.0.0.1
Remove-DnsServerForwarder -IPAddress fe80::... -Force
# remove old address records that don't point at 192.168.100.10, then:
Clear-DnsServerCache -Force ; ipconfig /flushdns
```

After that, `nslookup lab.local` answered instantly with `192.168.100.10`. Turning on DNS scavenging
keeps old records from piling up again.

## After migrating Wazuh to Docker, the VM's disk kept filling up

Disk usage on `docker01` was at 72% after the Docker migration, which seemed high for what should
have been a fairly small addition. Tracked it down step by step: `docker system df` accounted for
about 16.4 GB (expected, that's the Wazuh images and volumes), but `/var` alone was sitting at 35 GB
— a big, unexplained gap.

```bash
sudo du -sh /var/* 2>/dev/null | sort -rh | head -10
```

`/var/ossec` (the native, now-disabled Wazuh manager) turned out to be 12 GB — even though the
service itself was confirmed `inactive (dead)`. Drilling further:

```bash
sudo du -sh /var/ossec/queue/* 2>/dev/null | sort -rh | head -10
```

`/var/ossec/queue/vd` alone was 11 GB — the Vulnerability Detector's local CVE feed database (NVD,
Ubuntu OVAL, and so on), left over from when the native manager was still running. It's just
downloaded feed data, not configuration or agent state, and the Docker-based manager has its own
completely separate copy of the same thing in its own volume — so this was pure dead weight from the
migration, safe to remove:

```bash
sudo rm -rf /var/ossec/queue/vd/*
```

Lesson: after decommissioning a service, check what it left behind, not just whether it's still
running. A service being `disabled` and `inactive` doesn't mean its old data isn't still sitting on
disk — and vulnerability-feed databases in particular can be surprisingly large.

## Proxmox migration: virtio driver injection silently doesn't fire for Windows Server 2025

`autounattend-dc01.xml`'s `DriverPaths` block is supposed to load the virtio-scsi/virtio-net
drivers during Windows Setup so it can use `virtio-scsi-pci` instead of emulated SATA. It never
did. `X:\windows\setupact.log` in the WinPE shell (reached via `qm sendkey <vmid> shift-f10` for a
`cmd.exe`, no VNC/browser login needed) confirmed the answer file was found and marked "usable for
pass [windowsPE]" — but the PnP/driver-injection step was never evaluated at all (zero hits for
`pnp`/`vioscsi` in the log), and Setup silently fell back to the manual wizard with an empty disk
list. The driver itself wasn't the problem: `drvload e:\vioscsi\2k25\amd64\vioscsi.inf` from that
same WinPE shell loaded it manually without complaint, and the disk showed up right after in
`wmic diskdrive`. It's specifically the automatic injection path that's broken. Not debugged
further — SATA + `e1000` work natively with zero driver injection, and performance is irrelevant
for a lab. Full context: [docker-lab/05-hardware-migration.md](docker-lab/05-hardware-migration.md).

## Proxmox migration: the `specialize` pass never runs (open, worked around)

Both `autounattend-dc01.xml` and `autounattend-ws01.xml` copy the provisioning scripts onto the
disk during the `specialize` pass, so `FirstLogonCommands` can run them later without depending on
the ISO's drive letter. The pass never ran on either VM — `C:\Provision` simply didn't exist,
confirmed with `dir` in a live PowerShell session, even though the later `oobeSystem` pass
(autologon, local admin) demonstrably did run. Worked around by manually finding the ISO by volume
label (`Get-Volume` → label `AUTOUNATTEND`) and copying the scripts by hand before running
`setup-dc01.ps1`/`setup-ws01.ps1`. There's a second, independent bug hiding behind the first even if
it gets fixed: `%~dp0` is a batch-file token that doesn't reliably resolve inside an inline
`cmd /c "..."` call, so the `xcopy` step would likely still come up empty. Left open — the clean
fix is moving the copy logic into `FirstLogonCommands` (proven to run) instead of `specialize`.

## Proxmox migration: virtio-net TX checksum offload corrupts UDP behind the NAT bridge

`docker01` failed `apt`/`docker pull` intermittently with no obvious pattern after the move to
Proxmox — just enough dropped UDP (DNS in particular) to make provisioning flaky. Cause: virtio-net's
TX checksum offload computes the wrong checksum for UDP packets crossing Proxmox's NAT/masquerade
path on the isolated `vmbr1` segment, and the kernel trusts it, so the packet gets dropped
downstream. Fixed with a persistent systemd unit (a plain `ethtool -K eth0 tx off` doesn't survive a
reboot) — see [proxmox/docker01-network-fixes.md](proxmox/docker01-network-fixes.md) for the unit
file, now baked into `cloud-init-docker01.yaml` so a fresh VM gets it automatically.

## Proxmox migration: volume-restored files can end up owned by the wrong UID

After restoring the `wazuh_etc` named-volume tarball onto the new manager container, `local_rules.xml`
and `local_decoder.xml` were owned by a stray `1000:1000` instead of `wazuh:wazuh` (UID 999) — the
tarball restore preserves whatever UID/GID owned the files on the source, not what the target
container expects. Wazuh doesn't fail loudly: `wazuh-analysisd` just logs
`WARNING: (1103): Could not open file 'etc/rules/local_rules.xml' due to [(13)-(Permission denied)]`
and carries on with its stock ruleset, so a genuinely custom detection would silently never fire.
Fixed with `chown wazuh:wazuh` on both files plus a manager restart; `restore-stacks.sh` now does
this automatically. Same root cause as the missing `<integration>` block documented in
[docker-lab/05-hardware-migration.md](docker-lab/05-hardware-migration.md) — volume/tarball restores
need their result verified explicitly, not assumed.
