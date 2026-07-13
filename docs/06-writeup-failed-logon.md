# Write-up 1 — Investigating a failed-logon alert

Date: 2026-07-12 · By: Jonas · Lab: `lab.local`

## What I wanted to prove

That the whole chain works: someone does something on a Windows machine, the Wazuh agent picks it
up, the SIEM matches it to a rule, and I see a useful alert I can investigate. The test case is a
simple one every SOC sees constantly — failed logins (Windows event 4625).

## Setup

- WS01 — Windows 11 Pro, joined to the domain, running Wazuh agent 002
- DC01 — Windows Server 2025, runs the domain and DNS
- wazuh — Ubuntu, running Wazuh 4.14, at `192.168.100.30`
- All machines on the same isolated lab network (`192.168.100.0/24`)

## What I did

1. On WS01, at the login screen, I signed in as `LAB\mmustermann` with the wrong password on purpose,
   a few times in a row.
2. In the Wazuh dashboard (Threat Hunting → Events), I set the time to the last 15 minutes and
   filtered for:
   ```
   data.win.system.eventID : "4625"
   ```

## What I saw

Six alerts appeared within about 12 seconds, all from WS01. Opening one of them showed these details:

| Field | Value | What it means |
|---|---|---|
| `rule.description` | Logon Failure – Unknown user or bad password | Wazuh's plain-language summary |
| `rule.id` | `60122` | which Wazuh rule fired |
| `rule.level` | `5` | severity of a single failure |
| `targetUserName` | `mmustermann` | which account was targeted |
| `subStatus` | `0xC000006A` | wrong password (the account itself exists) |
| `logonType` | `2` | an interactive/console login |
| `rule.mitre.id` | `T1531` | the attack-technique tag Wazuh assigned |

### A nice extra: the domain defended itself

I couldn't keep guessing forever. After a number of wrong tries the domain's account lockout policy
kicked in and locked `mmustermann` automatically. That produces its own event (4740) on DC01, and
from then on the failures say `0xC0000234` ("account locked") instead. So I didn't just log the
attack — I watched a control actually stop it.

## Triage — is this a problem?

The real job isn't "an alert fired", it's deciding whether it matters. Here's how I read it:

- `subStatus 0xC000006A` tells me the account is real and only the password was wrong. That's what
  password guessing looks like, not a typo of some account that doesn't exist.
- Six failures in twelve seconds against one account isn't a human fat-fingering their password.
  That pattern is worth escalating.
- By contrast, one failed login from a known user in the middle of the workday is normal — no action
  needed.

Things that would make me treat it as more serious: an unusual source address, out-of-hours timing,
several different accounts being tried, or Wazuh's brute-force rule (60204) firing on many rapid
failures.

## Result

The full path works: something happens on the endpoint, the agent forwards it, Wazuh matches a rule,
and I get an alert I can actually investigate — plus I saw a real defense (account lockout) do its
job. Screenshot: `04-failed-login-alert`.
