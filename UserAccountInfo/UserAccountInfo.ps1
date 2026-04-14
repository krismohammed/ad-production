Import-Module ActiveDirectory

# Define variables based on domain
$currentDomain = (Get-WmiObject Win32ComputerSystem).Domain
$domainDN = (Get-ADDomain).DistinguishedName
$outputCSV = Join "$PSScriptRoot" 'UserAccountInfo.csv'

$ouEMP = "OU=Employees,OU=Users,$domainDN"
$ouCTR = "OU=Contractors,OU=Users,$domainDN"
$ouAdmins = "OU=Admins,OU=Users,$domainDN"
$ouDisabled = "OU=Disabled_Users,OU=Users,$domainDN"

# Gather required information from Active Directory
$Employees = Get-ADUser -Filter * -SearchBase $ouEMP -Property DisplayName, SamAccountName, UserPrincipalName, userCertificate, LastLogonDate, whenCreated, Enabled 
$Contractors = Get-ADUser -Filter * -SearchBase $ouCTR -Property DisplayName, SamAccountName, UserPrincipalName, userCertificate, LastLogonDate, whenCreated, Enabled 
$Admins = Get-ADUser -Filter * -SearchBase $ouAdmins -Property DisplayName, SamAccountName, UserPrincipalName, userCertificate, LastLogonDate, whenCreated, Enabled 
$Disabled_users = Get-ADUser -Filter * -SearchBase $ouDisabled -Property DisplayName, SamAccountName, UserPrincipalName, userCertificate, LastLogonDate, whenCreated, Enabled

# Combine information from each OU
$users = $Employees + $Contractors + $Admins + $Disabled_users

# Initialize an array to hold the processed user info
$userAccountInfo = @()

foreach ($user in $users) {
    # Extract user properties
    $logonName      = $user.UserPrincipalName -replace '\ .. *', ''
    $samAccountName = $user.SamAccountName
    $lastLogonDate  = if ($user.LastLogonDate) { $user.LastLogonDate.Date } else { $null }
    $accountStatus  = if ($user.Enabled) { "Enabled" } else { "Disabled" }
    $accountCreated = if ($user.whenCreated) { $user.whenCreated.Date } else { $null }

    # Obtain certificate expiration date if applicable
    $certExpirationDate = $null
    if ($user.userCertificate -and $user.userCertificate.Count -gt 0) {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509.Certificate2
            $cert.Import($user.userCertificate[0])
            $certExpirationDate = $cert.NotAfter.Date
        } catch {
            $certExpirationDate = $null
        }
    }

    # Create a custom object to store the information
    $userAccountInfo += [PSCustomObject]@{
        LogonName          = $logonName
        SamAccountName     = $samAccountName
        LastLogonDate      = $lastLogonDate
        AccountStatus      = $accountStatus
        CertExpirationDate = $certExpirationDate
        AccountCreated     = $accountCreated
    }
}

# Export to CSV
$userAccountInfo | Export-Csv -Path $outputCSV -NoTypeInformation -Encoding UTF8

Write-Output "Export complete. User account info has been saved to $outputCSV."
