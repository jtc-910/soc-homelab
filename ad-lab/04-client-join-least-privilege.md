# Step 2 — WS01, the Windows client, and joining the domain

WS01 is a normal Windows 11 machine that acts like an employee's computer. Joining it to the domain
means it now trusts DC01 for logins, and — more importantly for this lab — it becomes a source of
security logs that Wazuh can collect.

One thing to know up front: it has to be **Windows 11 Pro**. The Home edition simply can't join a
domain.

*Note: this covers the domain-join part of roadmap item 1.4. The least-privilege half — a standard
domain user without local admin rights on WS01 — is still open; see
[`../PORTFOLIO_ROADMAP.md`](../PORTFOLIO_ROADMAP.md).*

## 1. Create the virtual machine in UTM

- New VM → **Virtualize** → **Windows**, pick the Windows 11 ARM64 ISO
- **"Use Apple Virtualization" turned off** (QEMU engine), one network card on **Shared Network**
  with the values from [../00-lab-setup.md](../00-lab-setup.md)
- 4 GB RAM, 64 GB disk; install the guest tools after the first boot

## 2. Windows setup

- Choose the **Pro** edition.
- Windows 11 tries to force you to sign in with a Microsoft account. To create a plain local account
  instead, press `Shift+F10` at the network screen to open a command prompt and run
  `start ms-cxh:localonly` (on some builds the older `OOBE\BYPASSNRO` works). Then make a local
  account.

![Confirming the edition with winver on WS01 — Windows 11 Pro. (Note: Get-ComputerInfo's WindowsProductName field still says "Windows 10 Pro" on this build; that's a known cosmetic registry quirk, not an actual Windows 10 install — winver and the build number are the reliable way to check.)](../assets/screenshots/ad-lab-04-client-edition.png)

## 3. Fixed IP, and point DNS at the domain controller

Open **PowerShell as Administrator**:

```powershell
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.100.20 -PrefixLength 24 -DefaultGateway 192.168.100.15
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.100.10
```

This is the key part: the client's DNS server must be **DC01 (192.168.100.10)**. If it points
anywhere else, joining the domain fails, because the machine can't find the domain. Check it with:

```powershell
nslookup lab.local   # must answer 192.168.100.10
```

(If `nslookup` shows a weird `fe80::...` address and times out, that's an IPv6 issue I ran into —
the fix is in [../99-troubleshooting.md](../99-troubleshooting.md).)

## 4. Join the domain

```powershell
Add-Computer -DomainName "lab.local" -Restart
```

Log in as `LAB\Administrator` when it asks.

## 5. Check it worked

- After the restart, sign in with a domain account (`LAB\<user>`).
- On DC01, `Get-ADComputer WS01` should now list the machine.

![Signed in as a domain account on WS01 — whoami shows lab\... and the AD groups](../assets/screenshots/ad-lab-04-lab-login.png)

![WS01 using DC01 for DNS, nslookup lab.local resolving cleanly](../assets/screenshots/ad-lab-04-ws01-dns.png)
