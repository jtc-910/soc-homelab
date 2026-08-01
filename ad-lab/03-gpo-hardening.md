# Step 1.3 — Group policies: audit logging

Goal for this step: turn on more detailed Windows auditing through a group policy, so Wazuh has much
more to work with. By default, a Windows domain logs very little. Things like "a process started" or
"someone changed a user account" aren't logged at all unless you turn on the right audit categories.

This is also a prerequisite for later detection work (like catching Kerberoasting or a rogue admin
account being created) — those attacks are only visible if the right events are being logged in the
first place.

## What I turned on

I created one GPO (`Audit Policy - Lab`) linked to the domain, with these settings:

- **Advanced Audit Policy Configuration → Logon/Logoff → Logon** (Success and Failure) — a more
  detailed version of the normal 4624/4625 login events.
- **Advanced Audit Policy Configuration → Account Management → User Account Management** (Success and
  Failure) — logs when accounts are created, changed, or added to groups. This is what will let me
  catch a rogue admin account being created later.
- **Advanced Audit Policy Configuration → Detailed Tracking → Process Creation** (Success and
  Failure) — Windows event 4688, logged every time a process starts. This is one of the most useful
  events for a SOC analyst.
- **Administrative Templates → System → Audit Process Creation → Include command line in process
  creation events** — without this, event 4688 tells you a process started but not what arguments it
  was run with. Turning this on makes the event actually useful (you can see, for example, that
  `powershell.exe` was run with a suspicious encoded command).

## Screenshots

![The new "Audit Policy - Lab" GPO in the Group Policy Management Console, linked to the domain](../assets/screenshots/ad-lab-03-gpo-created.png)

![The three enabled audit categories in the GPO editor: Logon, User Account Management, Process Creation](../assets/screenshots/ad-lab-03-audit-categories.png)

!["Include command line in process creation events" turned on under Administrative Templates](../assets/screenshots/ad-lab-03-commandline-logging.png)

## Verifying it worked

```powershell
gpupdate /force
```

on DC01 and WS01.

![gpupdate /force applying the new policy](../assets/screenshots/ad-lab-03-gpupdate-forced.png)

Then checked that new events actually started arriving in Wazuh:

```
data.win.system.eventID : "4688"
```

<!-- still to add: a 4688 event in Wazuh, with the command line visible -->

## Why this matters for SOC work

Process-creation logging (with command lines) is one of the highest-value log sources for a SOC —
it's how you catch things like a script running from an unusual path, an encoded PowerShell command,
or a suspicious tool being launched. This maps to MITRE ATT&CK T1059 (Command and Scripting
Interpreter) and is the foundation for a lot of endpoint detection rules.

The account-management auditing is what will let me build the "rogue admin account" detection later
(roadmap item 2.3) — without it, that kind of change wouldn't show up at all.
