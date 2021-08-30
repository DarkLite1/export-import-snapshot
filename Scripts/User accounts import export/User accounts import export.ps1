<#
    .SYNOPSIS
        Export or import user rules.

    .DESCRIPTION
        This script should be run on a machine that has all the required
        users already created on the computer. Then run the script with action
        'Export' which will create a file containing the enabled user accounts.

        On another computer this script can be run with action 'Import' to
        recreate the required user accounts.

    .PARAMETER Action
        When action is 'Export' the data will be saved in the $DateFolder, when 
        action is 'Import' the data in the $DataFolder will be restored.

    .PARAMETER DataFolder
        Folder where to save or restore the user accounts

    .PARAMETER UserAccountsFileName
        Name of the file that contains all local user accounts that are enabled

    .PARAMETER UserPasswordsFileName
        Name of the file that contains all the passwords for user accounts that 
        need to be imported. This allows you to set passwords upfront for each
        account. 
        
        If this file is not present or the password is empty you will be 
        prompted to provide a password for the user to be created.

        When a user account already exist on the computer and no password is 
        available in the UserPasswordsFileName, the password will not be 
        changed for that user account.

    .EXAMPLE
        & 'C:\UserAccounts.ps1' -DataFolder 'C:\UserAccounts' -Action 'Export'

        Export all user accounts on the current computer to the folder 
        'C:\UserAccounts'

    .EXAMPLE
        & 'C:\UserAccounts.ps1' -DataFolder 'C:\UserAccounts' -Action 'Import'

        Restore all user accounts in the folder 'C:\UserAccounts' on the current computer
#>

[CmdletBinding()]
Param(
    [ValidateSet('Export', 'Import')]
    [Parameter(Mandatory)]
    [String]$Action,
    [Parameter(Mandatory)]
    [String]$DataFolder,
    [String]$UserAccountsFileName = 'UserAccounts.xml'
)

Begin {
    Try {
        $UserAccountsFile = Join-Path -Path $DataFolder -ChildPath $UserAccountsFileName

        #region Test DataFolder
        If ($Action -eq 'Export') {
            If (-not (Test-Path -LiteralPath $DataFolder -PathType Container)) {
                throw "Export folder '$DataFolder' not found"
            }
            If ((Get-ChildItem -Path $DataFolder | Measure-Object).Count -ne 0) {
                throw "Export folder '$DataFolder' not empty"
            }
        }
        else {
            If (-not (Test-Path -LiteralPath $DataFolder -PathType Container)) {
                throw "Import folder '$DataFolder' not found"
            }
            If ((Get-ChildItem -Path $DataFolder | Measure-Object).Count -eq 0) {
                throw "Import folder '$DataFolder' empty"
            }
            If (-not (Test-Path -LiteralPath $UserAccountsFile -PathType Leaf)) {
                throw "User accounts file '$UserAccountsFile' not found"
            }
        }
        #endregion
    }
    Catch {
        throw "$Action user accounts failed: $_"
    }
}

Process {
    Try {
        If ($Action -eq 'Export') {
            Write-Verbose "Export user accounts to file '$UserAccountsFile'"
            If ($users = Get-LocalUser | Where-Object { $_.Enabled }) {
                $users | ForEach-Object {
                    Write-Verbose "User account '$($_.Name)' description '$($_.description)'"
                }
                Write-Verbose "Export users to file '$UserAccountsFile'"
                $users | Select-Object -Property *, 
                @{Name = 'Password'; Expression = { '' } } | 
                Export-Clixml -LiteralPath $UserAccountsFile -EA Stop
            }
            else {
                throw 'No enabled local user accounts found'
            }
        }
        else {
            Write-Verbose "Import user accounts from file '$UserAccountsFile'"
            $importedUsers = Import-Clixml -LiteralPath $UserAccountsFile -EA Stop

            $knownComputerUsers = Get-LocalUser

            Function Set-NewPasswordHC {
                Param (
                    [Parameter(Mandatory)]
                    [String]$UserName,
                    [String]$UserPassword,
                    [Switch]$NewUser
                )

                if (-not $UserPassword) {
                    $UserPassword = Read-Host "Please type a password for user account '$UserName':"
                }

                Do {
                    try {
                        $isPasswordAccepted = $false
                        $params = @{
                            Name        = $user.Name 
                            Password    = ConvertTo-SecureString $UserPassword -AsPlainText -Force
                            ErrorAction = 'Stop'
                        }
                        if ($NewUser) {
                            New-LocalUser @params
                        }
                        else {
                            Set-LocalUser @params
                        }
                        $isPasswordAccepted = $true
                    }
                    catch [Microsoft.PowerShell.Commands.InvalidPasswordException] {
                        Write-Host "Password not accepted: $_" -ForegroundColor Red
                        $UserPassword = Read-Host "Please type a new password for user account '$UserName':"
                        $Error.RemoveAt(1)
                    }
                }
                while (-not $isPasswordAccepted)
            }

            foreach ($user in $importedUsers) {
                try {                    
                    Write-Verbose "User '$($user.Name)'"
                    $passwordParams = @{
                        UserName     = $user.Name 
                        UserPassword = $user.Password 
                        NewUser      = $false
                    }

                    #region Create incomplete user when not present
                    if ($knownComputerUsers.Name -NotContains $user.Name) {
                        $passwordParams.NewUser = $true
                        Set-NewPasswordHC @passwordParams
                    }
                    #endregion

                    #region Set user account details
                    $setUserParams = @{
                        Name                  = $user.Name
                        Description           = $user.Description
                        FullName              = $user.FullName
                        PasswordNeverExpires  = ![Boolean]$user.PasswordExpires
                        UserMayChangePassword = $user.UserMayChangePassword
                        ErrorAction           = 'Stop'
                    }
                    if ($user.AccountExpires) {
                        $setUserParams.AccountExpires = $user.AccountExpires
                    }
                    else {
                        $setUserParams.AccountNeverExpires = $true
                    }
                    Set-LocalUser @setUserParams
                    #endregion

                    if (-not $passwordParams.NewUser) {
                        if ($user.Password) {
                            Set-NewPasswordHC @passwordParams
                        }
                        else {
                            do { 
                                $answer = (
                                    Read-Host "Would you like to set a new password for user account '$($user.Name)'? [Y]es or [N]o"
                                ).ToLower()
                            } 
                            until ('y', 'n' -contains $answer)
                            if ($answer -eq 'y') {
                                Set-NewPasswordHC @passwordParams
                            }
                        }
                    }
                }
                catch {
                    Write-Error "Failed to create user account '$($user.Name)': $_"
                    $Error.RemoveAt(1)
                }
            }
        }
    }
    Catch {
        throw "$Action user accounts failed: $_"
    }
}