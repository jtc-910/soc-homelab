#!/usr/bin/env bash
# lab-healthcheck.sh -- end-to-end health check for the SOC homelab (roadmap 5.5).
#
# Runs from the admin Mac. Uses the existing SSH aliases:
#   pve      -> Proxmox host (root, key-only)
#   docker01 -> Wazuh/TheHive/Cortex/DVWA/Juice Shop host (via ProxyJump pve)
# Windows checks run through the QEMU guest agent (`qm guest exec` on pve, as SYSTEM),
# so DC01/WS01 need qemu-ga installed and `agent: enabled=1` set.
#
# Usage:
#   automation/lab-healthcheck.sh            read-only checks
#   automation/lab-healthcheck.sh --attack   also replays the brute-force test (10 bad
#                                            passwords against mmustermann on DC01) and
#                                            follows it to rule 60204 and a TheHive alert
#
# Exit code: 0 if every check passed, 1 otherwise. No secrets live in this file -- the
# indexer password and TheHive API key are read on docker01 at runtime.

set -u

PVE="${PVE_HOST:-pve}"
D01="${DOCKER01_HOST:-docker01}"
DC01_ID=110
WS01_ID=120
ATTACK=0
[ "${1:-}" = "--attack" ] && ATTACK=1

PASS=0
FAIL=0
FAILED=()

if [ -t 1 ]; then G=$'\e[32m'; R=$'\e[31m'; B=$'\e[1m'; N=$'\e[0m'; else G=; R=; B=; N=; fi

ok()      { PASS=$((PASS+1)); printf "  ${G}PASS${N}  %-44s %s\n" "$1" "${2:-}"; }
bad()     { FAIL=$((FAIL+1)); FAILED+=("$1"); printf "  ${R}FAIL${N}  %-44s %s\n" "$1" "${2:-}"; }
section() { printf "\n${B}== %s${N}\n" "$1"; }

# check NAME EXPECTED ACTUAL  -- exact string match
check() { if [ "$3" = "$2" ]; then ok "$1" "$3"; else bad "$1" "expected '$2', got '${3:-<empty>}'"; fi; }

# Results from a remote batch come back as lines "PASS|name|detail" / "FAIL|name|detail"
report() {
    local line status name detail
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        IFS='|' read -r status name detail <<<"$line"
        case "$status" in
            PASS) ok "$name" "$detail" ;;
            FAIL) bad "$name" "$detail" ;;
            *)    bad "unexpected output" "$line" ;;
        esac
    done
}

# Remote batches write into $TMP and are reported from the current shell -- piping into
# report would run it in a subshell and lose the counters (macOS bash 3.2 has no lastpipe).
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
report_tmp() {
    if [ -s "$TMP" ]; then report < "$TMP"; else bad "$1: no results" "remote batch returned nothing (see error above)"; fi
}

command -v jq >/dev/null || { echo "jq is required on this machine (macOS ships /usr/bin/jq)"; exit 1; }

# win VMID SCRIPT -- run a PowerShell script in a Windows guest via the guest agent.
# Passed as -EncodedCommand (UTF-16LE base64) so no quoting survives three shells.
win() {
    local b64
    b64=$(printf '%s' "$2" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')
    local raw
    raw=$(ssh -o BatchMode=yes "$PVE" "qm guest exec $1 --timeout 180 -- powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $b64" 2>&1)
    [ -n "${HC_DEBUG:-}" ] && printf '%s\n' "$raw" >&2
    printf '%s' "$raw" | jq -r '."out-data" // empty' 2>/dev/null | tr -d '\r'
}

# PowerShell helper prepended to every Windows batch
PS_HELPERS='
$ErrorActionPreference = "Continue"
# Not "R": that is a built-in alias for Invoke-History, and aliases win over functions
function Chk($name, [bool]$cond, $detail) {
    if ($cond) { "PASS|$name|$detail" } else { "FAIL|$name|$detail" }
}
function Agent-Localfiles {
    $c = Get-Content "C:/Program Files (x86)/ossec-agent/ossec.conf" -Raw
    ($c -match "Microsoft-Windows-Sysmon/Operational") -and ($c -match "Microsoft-Windows-PowerShell/Operational")
}
function Reg($path, $name) { (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name }
'

# --- 1. Proxmox host ---------------------------------------------------------------
section "Proxmox host ($PVE)"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$PVE" 'bash -s' <<'EOF' >"$TMP"; report_tmp "Proxmox host"
r() { if eval "$2"; then echo "PASS|$1|$3"; else echo "FAIL|$1|$3"; fi; }
for id in 100 110 120; do
    name=$(qm config $id | awk '/^name:/{print $2}')
    r "VM $id ($name) running" "qm status $id | grep -q running" "$(qm status $id | cut -d' ' -f2)"
    r "VM $id ($name) onboot" "qm config $id | grep -q '^onboot: 1'" "$(qm config $id | awk '/^startup:/{print $2}')"
done
for id in 110 120; do
    r "VM $id guest agent responds" "qm agent $id ping >/dev/null 2>&1" ""
done
r "backup job lab-weekly enabled" "grep -A8 '^vzdump: lab-weekly' /etc/pve/jobs.cfg | grep -q 'enabled 1'" "$(awk '/^vzdump: lab-weekly/{f=1} f&&/schedule/{print $2,$3;exit}' /etc/pve/jobs.cfg)"
newest=$(ls -t /mnt/pve-backup/dump/*.vma.zst 2>/dev/null | head -1)
age=$(( ( $(date +%s) - $(stat -c %Y "$newest" 2>/dev/null || echo 0) ) / 86400 ))
r "newest backup younger than 8 days" "[ -n '$newest' ] && [ $age -lt 8 ]" "${age}d old"
for j in sshd proxmox; do
    r "fail2ban jail $j" "fail2ban-client status $j >/dev/null 2>&1" ""
done
r "NAT for lab net (vmbr1 -> vmbr0)" "iptables -t nat -S POSTROUTING | grep -q '192.168.100.0/24 -o vmbr0 -j MASQUERADE'" ""
EOF

# --- 2. docker01 -------------------------------------------------------------------
section "docker01 (hardening, stacks, Wazuh pipeline)"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$D01" 'bash -s' <<'EOF' >"$TMP"; report_tmp "docker01"
r() { if eval "$2"; then echo "PASS|$1|$3"; else echo "FAIL|$1|$3"; fi; }
M=single-node-wazuh.manager-1
sshd=$(sudo sshd -T 2>/dev/null)
r "sshd: password login off" "grep -q '^passwordauthentication no' <<<\"\$sshd\"" ""
r "sshd: root login off" "grep -q '^permitrootlogin no' <<<\"\$sshd\"" ""
r "fail2ban sshd jail" "sudo fail2ban-client status sshd >/dev/null 2>&1" ""
r "ufw active, default deny" "sudo ufw status verbose | grep -q 'deny (incoming)'" ""
r "ufw rules limited to lab subnet" "! sudo ufw status | grep -q 'ALLOW IN *Anywhere'" "$(sudo ufw status | grep -c 'ALLOW IN *Anywhere') rule(s) open to Anywhere"
for s in ModemManager multipathd udisks2; do
    r "service $s not enabled" "! systemctl is-enabled --quiet $s 2>/dev/null" "$(systemctl is-enabled $s 2>&1)"
done
r "unattended-upgrades enabled" "systemctl is-enabled --quiet unattended-upgrades" ""
r "eth0 tx checksum offload off" "ethtool -k eth0 | grep -q 'tx-checksum-ip-generic: off'" ""
r "DNS resolution (apt/docker pull)" "getent hosts github.com >/dev/null" ""

up=$(docker ps --format '{{.Names}}' | sort | tr '\n' ' ')
for c in single-node-wazuh.manager-1 single-node-wazuh.indexer-1 single-node-wazuh.dashboard-1 \
         thehive cortex cassandra elasticsearch nginx dvwa juice-shop; do
    st=$(docker inspect -f '{{.State.Status}}/{{.RestartCount}}' $c 2>/dev/null)
    r "container $c" "[ \"\${st%%/*}\" = running ]" "$st"
done
unhealthy=$(docker ps --filter health=unhealthy --format '{{.Names}}' | tr '\n' ' ')
r "no unhealthy containers" "[ -z '$unhealthy' ]" "$unhealthy"

PW=$(grep -m1 -oP 'INDEXER_PASSWORD=\K\S+' ~/wazuh-docker/single-node/docker-compose.yml)
health=$(curl -sk -u admin:"$PW" https://localhost:9200/_cluster/health | jq -r .status)
r "indexer cluster health" "[ '$health' = green ]" "$health"

agents=$(docker exec $M /var/ossec/bin/agent_control -l)
for a in DC01 WS01; do
    r "Wazuh agent $a active" "grep -q 'Name: $a, .*Active' <<<\"\$agents\"" ""
done
own=$(docker exec $M stat -c '%U:%G' /var/ossec/etc/rules/local_rules.xml /var/ossec/etc/decoders/local_decoder.xml | sort -u | tr '\n' ' ')
r "local rules/decoders owned by wazuh" "[ '$own' = 'wazuh:wazuh ' ]" "$own"
r "custom-w2thive integration configured" "docker exec $M grep -q '<name>custom-w2thive</name>' /var/ossec/etc/ossec.conf" ""
r "wazuh-integratord running" "docker exec $M pgrep -f wazuh-integratord >/dev/null" ""
r "thehive4py importable (framework python)" "docker exec $M /var/ossec/framework/python/bin/python3 -c 'import thehive4py' 2>/dev/null" ""

code() { curl -sk -m 10 -o /dev/null -w '%{http_code}' "$1"; }
c=$(code https://localhost:443/);                 r "Wazuh dashboard :443" "[ '$c' = 302 ] || [ '$c' = 200 ]" "$c"
c=$(code https://localhost:8443/thehive/);        r "TheHive :8443/thehive" "[ '$c' = 200 ]" "$c"
c=$(code https://localhost:8443/cortex/api/status); r "Cortex :8443/cortex/api/status" "[ '$c' = 200 ]" "$c"
c=$(code http://localhost:8080/login.php);        r "DVWA :8080 (Apache really serving)" "[ '$c' = 200 ]" "$c"
c=$(code http://localhost:3000/);                 r "Juice Shop :3000" "[ '$c' = 200 ]" "$c"
EOF

# --- 3. DC01 -----------------------------------------------------------------------
section "DC01 (AD, GPO, shares, DHCP, DNS, telemetry)"
win $DC01_ID "$PS_HELPERS"'
Import-Module ActiveDirectory, GroupPolicy, DnsServer, DhcpServer -ErrorAction SilentlyContinue
$d = Get-ADDomain -ErrorAction SilentlyContinue
Chk "AD domain lab.local" ($d.DNSRoot -eq "lab.local") $d.DNSRoot
foreach ($ou in "Lab Users","Service Accounts") {
    Chk "OU $ou" ([bool](Get-ADOrganizationalUnit -Filter "Name -eq `"$ou`"")) ""
}
foreach ($g in "IT","Sales","Finance") { Chk "group $g" ([bool](Get-ADGroup -Filter "Name -eq `"$g`"")) "" }
$n = (Get-ADUser -Filter * -SearchBase $d.DistinguishedName | Where-Object { $_.DistinguishedName -match "OU=" }).Count
Chk "lab users in OUs (>= 14)" ($n -ge 14) "$n"
Chk "mmustermann exists" ([bool](Get-ADUser -Filter "SamAccountName -eq `"mmustermann`"")) ""
$spn = (Get-ADUser svc-sql -Properties ServicePrincipalName).ServicePrincipalName
Chk "svc-sql SPN" ($spn -contains "MSSQLSvc/db.lab.local:1433") "$spn"
$pp = Get-ADDefaultDomainPasswordPolicy
Chk "password policy (len 12, complex, lockout 0)" (($pp.MinPasswordLength -eq 12) -and $pp.ComplexityEnabled -and ($pp.LockoutThreshold -eq 0)) "len=$($pp.MinPasswordLength) lockout=$($pp.LockoutThreshold)"

$gpo = "Audit Policy - Lab"
$links = (Get-GPInheritance -Target $d.DistinguishedName).GpoLinks.DisplayName
Chk "GPO linked to domain" ($links -contains $gpo) ""
$vals = @(
  @("HKLM\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices","Deny_All",1),
  @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System","InactivityTimeoutSecs",900),
  @("HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging","EnableScriptBlockLogging",1),
  @("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit","ProcessCreationIncludeCmdLine_Enabled",1))
foreach ($v in $vals) {
    $x = (Get-GPRegistryValue -Name $gpo -Key $v[0] -ValueName $v[1] -ErrorAction SilentlyContinue).Value
    Chk "GPO value $($v[1])" ($x -eq $v[2]) "$x"
}
$ap = auditpol /get "/subcategory:Logon,Process Creation,User Account Management" /r | ConvertFrom-Csv
foreach ($row in $ap) { Chk "effective audit $($row.Subcategory)" ($row."Inclusion Setting" -eq "Success and Failure") $row."Inclusion Setting" }

foreach ($s in "IT","Sales","Finance") {
    $share = Get-SmbShare -Name $s -ErrorAction SilentlyContinue
    $acl = if ($share) { Get-Acl $share.Path } else { $null }
    $ids = if ($acl) { ($acl.Access | ForEach-Object { $_.IdentityReference.Value }) -join "," } else { "" }
    Chk "share $s (NTFS: LAB\$s + Domain Admins only)" ($share -and $acl.AreAccessRulesProtected -and ($ids -match "LAB\\$s") -and ($ids -notmatch "Everyone|Users")) $ids
}

$sc = Get-DhcpServerv4Scope -ScopeId 192.168.100.0 -ErrorAction SilentlyContinue
$rt = (Get-DhcpServerv4OptionValue -ScopeId 192.168.100.0 -OptionId 3 -ErrorAction SilentlyContinue).Value
Chk "DHCP scope active, router .1" (($sc.State -eq "Active") -and ($rt -contains "192.168.100.1")) "$($sc.State) $rt"

Chk "DNS CNAME fileserver" ([bool](Get-DnsServerResourceRecord -ZoneName lab.local -Name fileserver -RRType CName -ErrorAction SilentlyContinue)) ""
Chk "DNS MX" ([bool](Get-DnsServerResourceRecord -ZoneName lab.local -Name "@" -RRType MX -ErrorAction SilentlyContinue)) ""
Chk "DNS TXT (SPF)" ([bool](Get-DnsServerResourceRecord -ZoneName lab.local -Name "@" -RRType Txt -ErrorAction SilentlyContinue)) ""
$z = Get-DnsServerZone lab.local
Chk "zone transfer restricted" ($z.SecureSecondaries -ne "TransferAnyServer") "$($z.SecureSecondaries)"
$pol = Get-DnsServerQueryResolutionPolicy -ZoneName lab.local -ErrorAction SilentlyContinue
Chk "split-horizon policies (Fqdn-scoped)" (($pol.Count -eq 2) -and (($pol | Where-Object { -not ($_.Criteria.Criteria -match "portal") }).Count -eq 0)) "$($pol.Count) policies"
$r = (Resolve-DnsName dc01.lab.local -Server 127.0.0.1 -Type A -ErrorAction SilentlyContinue).IPAddress
Chk "dc01.lab.local still resolves" ($r -contains "192.168.100.10") "$r"

foreach ($svc in "NTDS","DNS","DHCPServer","Sysmon64","WazuhSvc") {
    $st = (Get-Service $svc -ErrorAction SilentlyContinue).Status
    Chk "service $svc" ($st -eq "Running") "$st"
}
Chk "agent forwards Sysmon + PowerShell channels" (Agent-Localfiles) ""
$lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE `"Windows%`"" | Select-Object -First 1
$days = [math]::Floor($lic.GracePeriodRemaining / 1440)
Chk "Windows eval > 30 days left" ($days -gt 30) "$days days"
' >"$TMP"; report_tmp DC01

# --- 4. WS01 -----------------------------------------------------------------------
section "WS01 (domain member, GPO applied, least privilege, telemetry)"
win $WS01_ID "$PS_HELPERS"'
$cs = Get-CimInstance Win32_ComputerSystem
Chk "joined to lab.local" ($cs.Domain -eq "lab.local") $cs.Domain
$dns = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses }).ServerAddresses
Chk "DNS server is DC01" ($dns -contains "192.168.100.10") "$dns"
$r = (Resolve-DnsName lab.local -Type A -ErrorAction SilentlyContinue).IPAddress
Chk "lab.local resolves to DC01" ($r -contains "192.168.100.10") "$r"
$p = (Resolve-DnsName portal.lab.local -Type A -ErrorAction SilentlyContinue).IPAddress
Chk "split-horizon: portal -> internal IP" ($p -contains "192.168.100.20") "$p"
Chk "SMB to DC01 reachable" ((Test-NetConnection 192.168.100.10 -Port 445 -WarningAction SilentlyContinue).TcpTestSucceeded) ""
Chk "GPO applied: Deny_All" ((Reg "HKLM:/SOFTWARE/Policies/Microsoft/Windows/RemovableStorageDevices" "Deny_All") -eq 1) ""
Chk "GPO applied: InactivityTimeoutSecs 900" ((Reg "HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/Policies/System" "InactivityTimeoutSecs") -eq 900) ""
Chk "GPO applied: ScriptBlockLogging" ((Reg "HKLM:/SOFTWARE/Policies/Microsoft/Windows/PowerShell/ScriptBlockLogging" "EnableScriptBlockLogging") -eq 1) ""
# Effective audit policy, not just the GPO content: a GPO can contain audit.csv and
# still not apply it (missing client-side extension registration, see ad-lab/03).
$ap = auditpol /get "/subcategory:Logon,Process Creation,User Account Management" /r | ConvertFrom-Csv
foreach ($row in $ap) { Chk "effective audit $($row.Subcategory)" ($row."Inclusion Setting" -eq "Success and Failure") $row."Inclusion Setting" }
$e = Get-WinEvent -FilterHashtable @{LogName="Security";Id=4688} -MaxEvents 1 -ErrorAction SilentlyContinue
Chk "4688 process-creation events being logged" ([bool]$e) "$($e.TimeCreated)"
$adm = (Get-LocalGroupMember -SID S-1-5-32-544 -ErrorAction SilentlyContinue).Name
$extra = $adm | Where-Object { $_ -match "^LAB\\" -and $_ -notmatch "Domain Admins" }
Chk "no domain users in local Administrators" (-not $extra) (($adm) -join ",")
foreach ($svc in "Sysmon64","WazuhSvc") {
    $st = (Get-Service $svc -ErrorAction SilentlyContinue).Status
    Chk "service $svc" ($st -eq "Running") "$st"
}
Chk "agent forwards Sysmon + PowerShell channels" (Agent-Localfiles) ""
' >"$TMP"; report_tmp WS01

# --- 5. Optional: brute-force replay end to end ------------------------------------
if [ $ATTACK -eq 1 ]; then
    section "Brute-force replay (DC01 -> Wazuh 60122/60204 -> TheHive)"
    start_ms=$(( $(date +%s) * 1000 ))
    start_iso=$(date -u +%Y-%m-%dT%H:%M:%S)
    win $DC01_ID '
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
$ctx = New-Object System.DirectoryServices.AccountManagement.PrincipalContext("Domain","lab.local")
$fails = 0
1..10 | ForEach-Object { if (-not $ctx.ValidateCredentials("mmustermann","Wrong-Password-$_")) { $fails++ } ; Start-Sleep -Milliseconds 500 }
"PASS|10 bad passwords sent|$fails rejected"
' >"$TMP"; report_tmp "brute-force trigger"
    echo "  ...waiting 60s for the agent -> manager -> integratord -> TheHive chain"
    sleep 60
    ssh -o BatchMode=yes "$D01" "START_ISO=$start_iso START_MS=$start_ms bash -s" <<'EOF' >"$TMP"; report_tmp "brute-force follow-up"
r() { if eval "$2"; then echo "PASS|$1|$3"; else echo "FAIL|$1|$3"; fi; }
M=single-node-wazuh.manager-1
recent=$(docker exec $M tail -n 5000 /var/ossec/logs/alerts/alerts.json | jq -c --arg t "$START_ISO" 'select(.timestamp[0:19] >= $t and .agent.name == "DC01") | .rule.id' 2>/dev/null)
n60122=$(grep -c '"60122"' <<<"$recent")
n60204=$(grep -c '"60204"' <<<"$recent")
r "rule 60122 (single logon failure) fired" "[ $n60122 -ge 8 ]" "${n60122}x"
r "rule 60204 (multiple logon failures) fired" "[ $n60204 -ge 1 ]" "${n60204}x"
K=$(docker exec $M grep -oP '<api_key>\K[^<]+' /var/ossec/etc/ossec.conf)
q='{"query":[{"_name":"listAlert"},{"_name":"filter","_and":[{"_gte":{"_field":"_createdAt","_value":'"$START_MS"'}},{"_like":{"_field":"title","_value":"*Multiple Windows Logon Failures*"}}]},{"_name":"page","from":0,"to":5}]}'
hits=$(curl -sk -H "Authorization: Bearer $K" -H 'Content-Type: application/json' https://localhost:8443/thehive/api/v1/query -d "$q" | jq 'length' 2>/dev/null)
r "TheHive alert created (via API)" "[ '${hits:-0}' -ge 1 ]" "${hits:-0} alert(s)"
EOF
fi

# --- Summary -----------------------------------------------------------------------
printf "\n${B}== Summary:${N} ${G}%d passed${N}, " "$PASS"
if [ $FAIL -eq 0 ]; then
    printf "${G}0 failed${N}\n"
    exit 0
fi
printf "${R}%d failed${N}\n" "$FAIL"
printf '  - %s\n' "${FAILED[@]}"
exit 1
