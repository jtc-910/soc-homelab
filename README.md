# SOC Homelab — Active Directory and Wazuh SIEM

This is a small security lab I built from scratch on my MacBook to learn the work of a
SOC (Security Operations Center) analyst. It runs a Windows domain, a Windows client that joins
that domain, and a Wazuh SIEM that collects the security logs from both machines. With that in
place I can generate real attacks later and watch them show up as alerts.

The idea is simple: instead of only collecting certificates, I want to show that I can actually
build the environment, produce real log data, and investigate it in a SIEM.

![Platform](https://img.shields.io/badge/platform-Apple%20Silicon%20ARM64-blue)
![SIEM](https://img.shields.io/badge/SIEM-Wazuh-orange)

---

## What's in the lab

![Network diagram of the SOC homelab: internet through a UTM gateway into the 192.168.100.0/24 shared network, with DC01, WS01, wazuh, and a planned kali machine](assets/diagrams/network-diagram.svg)

*Editable source: [assets/diagrams/network-diagram.drawio](assets/diagrams/network-diagram.drawio) (open with [diagrams.net](https://app.diagrams.net) / the draw.io desktop app).*

## The machines

| Role | Name | Operating system | IP address | RAM |
|---|---|---|---|---|
| Domain Controller | DC01 | Windows Server 2025 (ARM64) | 192.168.100.10 | 4 GB |
| Client | WS01 | Windows 11 Pro (ARM64) | 192.168.100.20 | 4 GB |
| SIEM | wazuh | Ubuntu Server (ARM64) | 192.168.100.30 | 4 GB |
| Attack machine (planned) | kali | Kali Linux (ARM64) | 192.168.100.40 | 2–3 GB |

- Domain name: `lab.local` · Network: `192.168.100.0/24` · Virtualization software: UTM
- My laptop is an Apple Silicon Mac (ARM), so every machine runs as an ARM64 virtual machine. That
  turned out to matter a lot, because a few things that are easy on a normal Intel PC needed
  workarounds here. I wrote all of those down in
  [docs/99-troubleshooting.md](docs/99-troubleshooting.md) so someone else (or future me) doesn't
  have to figure them out again.

## Build log

Each step has its own page with the exact commands I ran and the problems I hit.

| Step | What I did | Page | State |
|---|---|---|---|
| 0 | Get UTM and the install files ready | [docs/00-prerequisites.md](docs/00-prerequisites.md) | Done |
| 1 | Set up DC01, the domain controller | [docs/01-dc01-domain-controller.md](docs/01-dc01-domain-controller.md) | Done |
| 2 | Set up WS01 and join it to the domain | [docs/02-ws01-client-join.md](docs/02-ws01-client-join.md) | Done |
| 1.5 | Everyday admin tasks (group policies, Intune) | [docs/05-admin-tasks.md](docs/05-admin-tasks.md) | Planned |
| 3 | Install Wazuh and connect the agents | [docs/03-wazuh-siem.md](docs/03-wazuh-siem.md) | Done |
| 4 | Check that logs arrive and trigger a test alert | [docs/04-validation.md](docs/04-validation.md) | Done |
| Write-up | Investigating a failed-logon alert | [docs/06-writeup-failed-logon.md](docs/06-writeup-failed-logon.md) | Done |
| Notes | Every problem I ran into and how I fixed it | [docs/99-troubleshooting.md](docs/99-troubleshooting.md) | Ongoing |

## What I learned to do here

- **Active Directory:** create a domain, run DNS, make users and groups, join a client
- **SIEM work:** install Wazuh, connect agents, add Sysmon, read events, investigate an alert
- **Windows admin:** set things up with PowerShell, fixed IP addresses, roles and features
- **Linux admin:** install Ubuntu Server, set the network, install software from the terminal
- **Virtualization and networking:** run several VMs on a Mac and get them to talk to each other
- **Writing it down:** clear step-by-step notes, a diagram, and one proper investigation write-up

## What's next

1. Core lab (this repo): domain controller, client, and Wazuh — done
2. Attack the domain from Kali (Kerberoasting, Pass-the-Hash) and detect it in Wazuh — planned
3. A web-application firewall project (nginx + ModSecurity against a vulnerable app) — planned
4. Bring it together: correlate web attacks and domain attacks in one dashboard — planned

---

*Built and documented by Jonas as part of a career change into security operations.*
