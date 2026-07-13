# Step 4 — Checking the whole thing actually works

Building the machines is one thing; proving that a security event on a Windows machine really turns
into an alert in the SIEM is the point of the whole lab. This step is that proof.

## What I checked

1. **Both agents are active** — in the Wazuh dashboard, DC01 and WS01 both show up and say "active".
2. **Windows logs are arriving** — filtering the dashboard by `agent.name: DC01` or `WS01` shows
   login and system events coming in.
3. **Sysmon logs are arriving** — filtering for
   `data.win.system.channel: "Microsoft-Windows-Sysmon/Operational"` shows detailed events like a
   program starting (event ID 1).
4. **A test attack is detected** — I typed a wrong password a few times on WS01 (a mini
   "someone's guessing the password" scenario). Each failed attempt is Windows event 4625, and each
   one showed up in Wazuh as an alert.
5. **DNS still fine** — `nslookup lab.local` from WS01 answers with DC01's address.

## When I considered this step done

- The domain `lab.local` is up and WS01 is joined to it
- Wazuh is reachable and both agents are active
- Sysmon events are visible, and a deliberate wrong-password attempt appears as an alert
- Screenshots taken (see the [checklist](../assets/screenshots/README.md))

## How I write up an investigation

For anything worth showing, I use the same simple structure so it reads like a real analyst's note:

1. Goal — what I was testing and why
2. Environment — which machines, versions, IPs
3. Steps — what I actually did
4. What I observed — the events/fields
5. Triage — is this normal or suspicious, and what would I do about it
6. Why it matters for SOC work

The failed-logon investigation written this way is in
[06-writeup-failed-logon.md](06-writeup-failed-logon.md).

Next up: set up Kali and run a real attack against the domain, then find it in Wazuh.
