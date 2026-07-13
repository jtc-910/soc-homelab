# Step 1.5 — Everyday Windows admin tasks (planned)

There's a Microsoft certification called MD-102 about managing Windows machines. Instead of studying
for the exam, I decided to actually *do* the tasks it covers in this lab and write them up. For a
SOC role, showing "here's the environment I built and manage" is more convincing than the badge, and
some of these tasks (especially the audit settings) directly produce more logs for Wazuh to work
with.

This step is still on my to-do list. I'm keeping it here as a plan.

## Part A — On the Windows domain (DC01 and WS01)

These are things a normal IT admin sets up in a company:

- Organize the domain into folders (organizational units): Lab Users, Workstations, Servers,
  Service Accounts
- Create some users and groups
- A group policy for passwords and account lockout (minimum length, complexity, lock after X wrong
  tries)
- A group policy that maps a network drive for a group
- A basic security policy (block USB storage, lock the screen after a while)
- A shared folder with proper permissions, tested with different users
- AppLocker: allow only approved programs, block an unsigned one on WS01
- LAPS: automatically rotate the local admin password and store it safely in the domain
- Turn on detailed audit logging (logins, process creation, account changes). This is the important
  one for me, because those extra events flow straight into Wazuh and give it more to detect.

Why this matters for SOC work: to trust a log source, you have to understand how it's configured.
Knowing which setting produces which Windows event ID (4624 for logon, 4625 for failed logon, 4688
for a new process, and so on) is everyday triage knowledge.

## Part B — Cloud management (Microsoft Entra and Intune)

The modern half of Windows management happens in the cloud. Microsoft offers a free developer tenant
I can use to practice:

- Create a free Microsoft 365 Developer tenant
- Make cloud users and groups in Entra ID
- Enroll WS01 into Intune (cloud device management)
- A compliance policy (e.g. require disk encryption and a firewall) and watch WS01 report as
  compliant or not
- A configuration profile that pushes a setting to the machine
- A basic Conditional Access rule (only compliant devices may sign in), in report-only mode first
- Deploy an app to WS01 through Intune
- Set up Windows Update rings

Why this matters for SOC work: the sign-in logs and device-compliance data from Entra and Intune are
exactly the kind of signals a cloud SIEM (Microsoft Sentinel) works with later. Managing them now
means I'll already understand where those signals come from.

## Note

The Windows 11 ARM client enrolls into Intune like any other Windows machine. If some setting behaves
oddly on ARM, I'll write it down in [99-troubleshooting](99-troubleshooting.md).
