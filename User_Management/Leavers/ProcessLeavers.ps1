Import-Module ActiveDirectory

# Define variables based on domain
$currentDomain = (Get-WmiObject Win32ComputerSystem).Domain
$domainDN = (Get-ADDomain).DistinguishedName
$jsonPath = Join "$PSScriptRoot" 'Leavers.json'
$outputCSV = Join "$PSScriptRoot" 'Leavers.csv'
$LeaversOU = "OU=Leavers,OU=Users,$domainDN"
$UsersOU = "OU=Users,$domainDN"

# Initialize an array to hold the leaver usernames
$leaverUsernames = @()

# Load the JSON file
$json = Get-Content -Path $jsonPath -ErrorAction SilentlyContinue | ConvertFrom-Json

$today = Get-Date

# Loop through each user in the JSON file
foreach ($user in $json.users) {
    $username = $user.username

    # Search the OU for the user account
    $userAccount = Get-ADUser -Filter "SamAccountName -eq '$username'" -SearchBase $UsersOU -ErrorAction SilentlyContinue

    if($userAccount){
        $isDisabled = -not $userAccount.Enabled
        $inLeaversOU = ($userAccount.DistinguishedName -like "*$LeaversOU*")

        # Update account description to reflect Leaver status and date
        Set-ADUser -Identity $userAccount -Description "Account is disabled and marked as 'Leaver' on $($today.ToShortDateString())"

        # Disable the account if not already disabled
        if (-not $isDisabled) {
            Write-Host "Disabling account '$username'..." -ForegroundColor Green
            Disable-ADAccount -Identity $userAccount
        }
        else {
            Write-Host "User account '$username' is already disabled." -ForegroundColor DarkGreen
        }

        # Move the account to the Leavers OU
        if (-not $inLeaversOU) {
            Write-Host "Moving account '$username' to Leavers OU" -ForegroundColor Green
            Move-ADObject -Identity $userAccount.DistinguishedName -TargetPath $LeaversOU
        }
        else {
            Write-Host "User account '$username' is already marked as a 'Leaver'." -ForegroundColor DarkGreen
        }

        # Create a custom object to store the information
        if (-not $inLeaversOU) {
            $csvData = [PSCustomObject]@{
                FirstName   = $user.firstName
                LastName    = $user.lastName
                Username    = $user.username
                Description = "Account is disabled and marked as 'Leaver' on $($today.ToShortDateString())"
            }
            # Export to CSV
            $csvData | Export-Csv -Path $outputCSV -Append -NoTypeInformation

            # Add username to the list of processed users
            $leaverUsernames += $username
        }
    }
    else {
        Write-Host "User account '$username' not found." -ForegroundColor Yellow
    }
}

# Wait for 10 seconds to read output
Start-Sleep -Seconds 10
