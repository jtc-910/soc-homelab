# Creates a batch of test users in the "Lab Users" OU and adds each one to a department group.
# Run on DC01 as a domain admin.

$users = @(
    @{First="Anna";   Last="Bauer";     Group="IT"}
    @{First="Ben";    Last="Fischer";   Group="IT"}
    @{First="Clara";  Last="Wagner";    Group="IT"}
    @{First="David";  Last="Schmidt";   Group="Sales"}
    @{First="Elena";  Last="Weber";     Group="Sales"}
    @{First="Felix";  Last="Meyer";     Group="Sales"}
    @{First="Greta";  Last="Koch";      Group="Sales"}
    @{First="Hannes"; Last="Richter";   Group="Finance"}
    @{First="Ines";   Last="Klein";     Group="Finance"}
    @{First="Jonas";  Last="Wolf";      Group="Finance"}
    @{First="Kira";   Last="Schulz";    Group="IT"}
    @{First="Leon";   Last="Neumann";   Group="Sales"}
)

# Lab-only placeholder password. ChangePasswordAtLogon forces each user to set their own on first
# login, so this value never actually gets used to sign in.
$defaultPassword = ConvertTo-SecureString "Passw0rd!ChangeMe" -AsPlainText -Force

foreach ($u in $users) {
    $sam = ($u.First.Substring(0,1) + $u.Last).ToLower()

    New-ADUser `
        -Name "$($u.First) $($u.Last)" `
        -GivenName $u.First `
        -Surname $u.Last `
        -SamAccountName $sam `
        -UserPrincipalName "$sam@lab.local" `
        -Path "OU=Lab Users,DC=lab,DC=local" `
        -AccountPassword $defaultPassword `
        -ChangePasswordAtLogon $true `
        -Enabled $true

    Add-ADGroupMember -Identity $u.Group -Members $sam
}
