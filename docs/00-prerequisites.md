# Step 0 — Getting everything ready

Before building anything, I needed the virtualization software and the install files (ISOs) for
each machine, plus a plan for how the network would work.

## My computer

- MacBook Pro (M1 Pro), 16 GB RAM, macOS
- **UTM** — the free app I use to run virtual machines on a Mac: https://mac.getutm.app

A note on memory: with only 16 GB, macOS itself already needs a good chunk, so I don't run all the
VMs at once. Two or three at a time is fine. This isn't a real problem, just something to keep in
mind so the laptop doesn't crawl.

## The install files (ISOs)

Because my Mac is ARM (Apple Silicon), I need the **ARM64** version of every operating system, not
the normal Intel/x64 one.

| Operating system | Edition | Where I got it |
|---|---|---|
| Windows Server 2025 | Standard (with desktop) | An ARM64 Insider build (see the note below) |
| Windows 11 | **Pro** (Home can't join a domain) | [Microsoft's official ARM64 download](https://www.microsoft.com/en-us/software-download/windows11arm64) |
| Ubuntu Server (ARM64) | LTS | https://ubuntu.com/download/server/arm |

Store all the ISOs in one folder, e.g. `~/Homelab/ISOs/`.

### Why the Windows Server file is a bit special

Microsoft does not offer a normal download of Windows Server for ARM. The only ARM version is a
preview ("Insider") build, and Microsoft even pulled those files from its own update servers for a
while. I first tried the official Intel/x64 Server ISO and ran it through emulation, but that was
slow and the installer hit a bug, so I switched to the ARM preview build instead. It runs natively
and fast.

Because that ARM build comes from an unofficial mirror, I only use it inside an isolated lab machine
with no real data on it, and I wrote down exactly which build it is. The full story is in
[docs/01](01-dc01-domain-controller.md).

### The Windows 11 file is easy

Microsoft now offers an official ARM64 Windows 11 ISO you can just download:
[microsoft.com/software-download/windows11arm64](https://www.microsoft.com/en-us/software-download/windows11arm64).
Pick the "Multi-Edition ISO for ARM64", download it, and choose **Pro** during setup. (Windows 11
Home cannot join a domain, so it has to be Pro.)

## The network plan (this was the hard part)

Getting the virtual machines to both reach the internet *and* see each other took me a long time,
so here is the setup that finally worked.

All VMs run on UTM's **QEMU** engine, and each VM has **one** network card set to **Shared Network**.
The important trick: by default UTM puts every VM on its own separate little network, so they can't
talk to each other. To fix that, I opened the advanced network settings on **every** VM and typed in
the **same** values by hand:

- Network Mode: **Shared Network**
- Guest Network: `192.168.100.0/24`
- DHCP Start: `192.168.100.15`
- DHCP End: `192.168.100.50`
- Network card model: **virtio-net-pci**

With that, all machines land on the same `192.168.100.0/24` network. They can reach each other,
they have internet, and they're still shielded from my home network. One network card per VM, no
complicated setups. (I found this trick on a blog by kilala.nl; link is in the troubleshooting
notes.)

Addresses I use:

- Gateway (the way out to the internet): `192.168.100.15`
- Fixed IPs: DC01 `.10`, WS01 `.20`, wazuh `.30`, kali `.40` (all use gateway `.15`)
- The client and server use **DC01 (192.168.100.10)** as their DNS server. DC01 itself uses a
  forwarder (`1.1.1.1`) so it can still look up internet names.

## Order I built things in

DC01 first (it provides the domain and DNS everything else depends on), then WS01, then Wazuh.
