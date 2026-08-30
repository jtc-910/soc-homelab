#Requires -RunAsAdministrator
<#
.SYNOPSIS
  WS01 provisioning: static IP pointed at DC01 for DNS, then domain join. Fired once
  by autounattend-ws01.xml's FirstLogonCommands.

.NOTES
  Mirrors ad-lab/04-client-join-least-privilege.md. Must run after DC01 is fully up
  (setup-dc01.ps1 phase 2 complete) -- WS01 can't resolve or join the domain otherwise.
#>

$ErrorActionPreference = "Stop"
$LogFile = "C:\Provision\setup-ws01.log"
function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

$IfAlias    = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1 -ExpandProperty Name)
$StaticIP   = "192.168.100.20"
$Gateway    = "192.168.100.1"
$DcIP       = "192.168.100.10"
$DomainName = "lab.local"

Log "Interface: $IfAlias -> $StaticIP/24 via $Gateway, DNS $DcIP"
New-NetIPAddress -InterfaceAlias $IfAlias -IPAddress $StaticIP -PrefixLength 24 -DefaultGateway $Gateway -ErrorAction SilentlyContinue
Set-DnsClientServerAddress -InterfaceAlias $IfAlias -ServerAddresses $DcIP

Log "Waiting for DC01 to answer for $DomainName (up to 10 minutes -- DC01 may still be mid-promotion)"
$deadline = (Get-Date).AddMinutes(10)
$resolved = $false
do {
    Start-Sleep -Seconds 15
    try {
        $result = Resolve-DnsName -Name $DomainName -Server $DcIP -ErrorAction Stop
        $resolved = $true
    } catch {
        Log "Not resolvable yet, retrying..."
    }
} until ($resolved -or (Get-Date) -gt $deadline)

if (-not $resolved) {
    Log "ERROR: could not resolve $DomainName via $DcIP after 10 minutes. Domain join skipped -- run this script again manually once DC01 is confirmed up."
    exit 1
}

# Domain-join needs credentials -- Administrator's password is the same lab-only
# placeholder set in autounattend-dc01.xml's local-admin block, since that account is
# also the domain Administrator once the forest exists on top of it.
Log "Joining domain $DomainName"
$cred = New-Object System.Management.Automation.PSCredential(
    "LAB\Administrator",
    (ConvertTo-SecureString "ChangeMe-LabOnly!2026" -AsPlainText -Force)
)
Add-Computer -DomainName $DomainName -Credential $cred -Restart -Force

# Execution does not continue past here -- Add-Computer -Restart reboots the machine.
# After reboot, WS01 is domain-joined; next steps are install-sysmon-wazuh-agent.ps1
# and the GPO/least-privilege checks in ad-lab/04-client-join-least-privilege.md.
