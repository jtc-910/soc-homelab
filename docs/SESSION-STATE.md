# Where the lab stands, and what's next

Last updated: 2026-07-13

## Done — the core lab works

- DC01 (Windows Server 2025, ARM): domain `lab.local` up, DNS running, test users including
  `svc-sql` with an SPN for a later attack.
- WS01 (Windows 11 Pro, ARM): joined to the domain.
- Wazuh (Ubuntu, ARM): installed, dashboard reachable, both agents active, Sysmon added.
- Validation done: a wrong-password test on WS01 showed up as an alert in Wazuh
  (see `docs/06-writeup-failed-logon.md`).
- Networking finally solved: all VMs on the same UTM engine (QEMU), each with one network card on
  Shared Network using the same manually-entered settings, so they share one network with internet.
  DC01 `.10`, WS01 `.20`, wazuh `.30`, gateway `.15`.
- DNS cleaned up on DC01: removed the dead IPv6 forwarder and stale A/AAAA records that were
  causing lookup timeouts.
- Real network diagram added: `assets/diagrams/network-diagram.svg` (embedded in the README) with
  an editable `.drawio` source next to it.
- All screenshots are now embedded directly in docs/00–04 and docs/06, not just referenced by
  filename — the full set (edition checks, Sysmon events, dashboard overview) is complete.

## Still to do

- Everyday admin tasks (group policies, especially audit logging, plus Intune/Entra) — `docs/05`.
- Set up Kali and attack the domain (Kerberoasting against `svc-sql`, Pass-the-Hash), then find the
  attack in Wazuh.

## Useful links

- The blog post that solved the networking: https://www.kilala.nl/index.php?id=2613
