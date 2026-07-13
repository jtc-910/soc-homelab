# Where the lab stands, and what's next

Last updated: 2026-07-13

For the full, phased plan see [`PORTFOLIO_ROADMAP.md`](PORTFOLIO_ROADMAP.md) — that file now tracks
what's planned and what's done (marked with ✅/🚧). This page is just a shorter, technical
"where exactly things stand" note.

## Repo structure (reorganized to match the roadmap's phases)

- `00-lab-setup.md`, `04-validation.md`, `99-troubleshooting.md` — project-level docs, at the root.
- `ad-lab/` — on-prem Active Directory work (domain setup, client join, later GPOs/ACLs).
- `siem-wazuh/` — the Wazuh SIEM deployment.
- `incident-writeups/` — investigation write-ups.
- `linux-lab/`, `network/`, `cloud-iam/`, `hardening/`, `automation/` — not created yet; they'll show
  up once there's real content for them (see the roadmap for what goes where).
- `docs/05-admin-tasks.md` is a leftover pointer file — couldn't be deleted from this session, points
  to the roadmap instead.

## Done — the core lab works

- DC01 (Windows Server 2025, ARM): domain `lab.local` up, DNS running, test users including
  `svc-sql` with an SPN for a later attack.
- WS01 (Windows 11 Pro, ARM): joined to the domain (least-privilege standard user still open).
- Wazuh (Ubuntu, ARM): installed, dashboard reachable, both agents active, Sysmon added.
- Validation done: a wrong-password test on WS01 showed up as an alert in Wazuh
  (see `incident-writeups/01-bruteforce.md`).
- Networking finally solved: all VMs on the same UTM engine (QEMU), each with one network card on
  Shared Network using the same manually-entered settings, so they share one network with internet.
  DC01 `.10`, WS01 `.20`, wazuh `.30`, gateway `.15`.
- DNS cleaned up on DC01: removed the dead IPv6 forwarder and stale A/AAAA records that were
  causing lookup timeouts.
- Real network diagram added: `assets/diagrams/network-diagram.svg` (embedded in the README) with
  an editable `.drawio` source next to it.
- All screenshots are embedded directly in the docs, not just referenced by filename — the full set
  (edition checks, Sysmon events, dashboard overview) is complete.

## Still to do (see PORTFOLIO_ROADMAP.md for the full list)

- Next up: Phase 1.3, the audit-logging GPO — brings more Wazuh telemetry right away.
- Then the rest of Phase 1: users/groups/OUs (1.2), least privilege on WS01 (1.4), file-server ACLs
  (1.5), and hardening the Wazuh Linux box (1.7).
- After that: Kali against the domain (Kerberoasting against `svc-sql`, Pass-the-Hash) — Phase 2.3
  territory, plus the SSH-focused Linux detection work (2.7, 2.8).
- pfSense/OpenVPN (Phase 3) deliberately pushed later — decided not to redo the network mid-build.

## Useful links

- The blog post that solved the networking: https://www.kilala.nl/index.php?id=2613
