 # Problems I ran into (and how I fixed them)

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

## Domain controller setup failed with error 0x8007000B

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

## The Windows Server x64 installer wouldn't accept "no product key"

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

## The big one: getting the machines to talk to each other

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
