Import-Module ActiveDirectory

# Define variables based on domain
$currentDomain = (Get-WmiObject Win32ComputerSystem).Domain
$domainDN = (Get-ADDomain).DistinguishedName
$jsonPath = Join "$PSScriptRoot" 'Users.json'
$employeeOU = "OU=Employees,OU=Users,$domainDN"
$contractorOU = "OU=Contractors,OU=Users,$domainDN"
$profilePath = "\\share-path.domain\network_profiles"
$upnSuffix = "121005" # if using smart card such as CAC
$domain = "mil" # for DoD domains

# Check for JSON file
if(-not(Test-path)) {
    Write-Error "JSON file is not found at $jsonPath."

}

# Load Json file
try {
    $jsonContent = Get-Content $jsonPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to load JSON file."
    exit 1
}

# Function to generate random password
function Get-RandomPassword {
    param(
        [int]$Length = 15,
        $ValidChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+{}\;:,.<>?/'
    )
    do {
        $Password -Join ($ValidChars.ToCharArray() | Get-Random -Count $Length | ForEach-Object {[char]$_ })
    } until ($Password -match '/d' -and $Password -match '[A-Z]' -and $Password -match '[!@#$%^&*()_+{}\;:,.<>?/]')
    return $Password
}

# Function to determin if UPN exists
function Test-UPNExists {
    param ( [string]$UPN)
    return [bool](Get-ADUser -Filter { UserPrincipalName -eq $UPN } -ErrorAction SilentlyContinue)
}

# Functiont to get a unique display name
function Get-UniqueName {
    param ( 
        [string]$FirstName,
        [string]$LastName
    )
    $name = "$FirstName $LastName"
    $i = 1
    while (Get-ADUser -Filter { Name -eq $name } -ErrorAction SilentlyContinue) {
        $name = "$FirstName $LastName$i"
        $i++
    }
    return $name
}

# Function to create or validate AD user
function Set-ADUserAccount {
    param(
        [object]$User,
        [SecureString]$Password
    )

    $samAccountName    = $User.username
    
    $userPrincipalName = "$($User.userPrincipalName).$upnSuffix@$domain"
    $displayName       = "$($User.firstName) $($User.lastName) $($User.accountType.toUpper())"
    $description       = if ($User.accountType -eq "fte") { "Full-Time Employee" } else { "Contractor" }
    $OU                = if ($User.accountType -eq "fte") { $employeeOU } else { $contractorOU }
    $userProfilePath   = $profilePath + $samAccountName
    $name              = Get-UniqueName $User.firstName $User.lastName

    if (Test-UPNExists $userPrincipalName) {
        Write-Host "Account '$displayName' already exists. Skipping..." -ForegroundColor Green
        return
    }

    try {
        New-ADUser `
            -SameAccountName        $samAccountName `
            -UserPrincipalName      $userPrincipalName `
            -Name                   $name `
            -GivenName              $User.firstName `
            -Surname                $User.lastName `
            -DisplayName            $displayName `
            -Description            $description `
            -Path                   $OU `
            -AccountPassword        $Password `
            -ProfilePath            $profilePath `
            -SmartcardLogonRequired $false `
            -Enabled                $true

        Write-Host "Created account for '$displayName' and added to $OU successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to create account '$samAccountName': $_"
    }
}

$password = Get-RandomPassword | ConvertTo-SecureString -AsPlainText -Force

# Process each user in the JSON
foreach ($user in $jsonContent.users) {
    Set-ADUserAccount -User $user -Password $password
}

Write-Host "`nUser creation process complete."
 
