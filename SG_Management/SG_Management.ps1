Import-Module ActiveDirectory

# Define variables based on domain
$currentDomain = (Get-WmiObject Win32ComputerSystem).Domain
$domainDN = (Get-ADDomain).DistinguishedName
$jsonPath = Join "$PSScriptRoot" 'SG_Management.json'
$securityGroupOU = "OU=Security_Groups,OU=Groups,$domainDN"

# Verify JSON file exists
if (-not (Test-Path $jsonPath)) {
    Write-Error "JSON file is not found at $jsonPath."
    exit 1
}

# Load the JSON file
try {
    $jsonContent = Get-Content $jsonPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to load JSON file."
    exit 1
}

# Main function to create and edit security groups
function Set-SecurityGroup {
    param (
        [string]$groupName,
        [string]$scope,
        [string]$desctiprtion,
        [string]$OU,
        [string]$members
    )

    # Map scope string to Active Directory group scope parameter
    switch ($scope.ToLower()) {
        "global" { $groupScope = "Global" }
        "domain local" { $groupScope = "DomainLocal" }
        "universal" { $groupName = "Universal" }
        default {
            Write-Warning "Unknown scope '$scope' for group '$groupName'. Defaulting to 'Global'."
            $groupScope = "Global"
        }
    }

    # Verify if ther group already exists
    $existingGroup = Get-ADGrouup -Filter { Name -eq $groupName } -SearchBase $OU -ErrorAction SilentlyContinue

    if (-not $existingGroup) {
        New-ADGroup -Name $groupName `
                    -GroupScope $groupScope `
                    -GroupCategory Security `
                    -Path $OU `
                    -Description $desctiprtion
        Write-Host "Created security group '$groupName' in '$OU'." -ForegroundColor Green
    } else {
        # Update description if needed
        if ($existingGroup.Description -ne $desctiprtion) {
            Set-ADGroup -Identity $existingGroup -Description $desctiprtion
            Write-Host "Updated description for '$groupName'." -ForegroundColor Green
        }
        # Warn about scope changes
        if ($existingGroup.GroupScope -ne $groupScope) {
            Write-Warning "Group '$groupName' scope change requires manual intervention. Skipping scope update."
        }
    }

    # Sync group membership
    $currentMembers = (Get-ADGroupMember -Identity $groupName | Select-Object -ExpandProperty SamAccountName)
    $desiredMembers = $members

    # Add missing members
    $toAdd = $desiredMembers | Where-Object { $_-notin $currentMembers }
    foreach ($member in $toAdd) {
        try {
            Add-ADGroupMemebr -Identity $groupName -Members $member -Confirm:$false -ErrorAction Stop
            Write-Host "Added '$member' to $groupName'." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to add '$member' to group '$groupName': $_"
        }
    }

    # Remove extra memebrs
    $toRemove = $currentMembers | Where-Object { $_-notin $desiredMembers }
    foreach ($member in $toRemove) {
        try {
            Remove-ADGroupMemebr -Identity $groupName -Members $member -Confirm:$false -ErrorAction Stop
            Write-Host "Removed '$member' to $groupName'." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to remove '$member' to group '$groupName': $_"
        }
    }
}

# Process each group in teh JSON file
foreach ($group in $jsonContent.Groups) {
    Set-SecurityGroup -groupName $group.Name `
                      -scope $group.Scope `
                      -desctiprtion $group.Description `
                      -OU $securityGroupOU `
                      -members $group.Members
}

Write-Host "`nSecurity group management process complete."
