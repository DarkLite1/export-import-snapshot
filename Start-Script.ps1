<#
    .SYNOPSIS
        Create or restore a snapshot of the current machine.

    .DESCRIPTION
        This script is intended to be run from a USB stick and is portable.

        Step 1: Configure the current machine correctly in Windows.

        Step 2: Plug in the USB stick and run this script on the correctly 
        configured machine to create a snapshot. Simply set $Action to 
        'CreateSnapshot' and set the $Snapshot items to '$true' for the 
        data you want to collect.

        At this point a snapshot is created and saved on the USB stick in the
        folder 'Snapshots'.

        Step 3: On another machine, where you want to restore the snapshot: 
        Plug in the USB stick and run this script with $Action set to 
        'RestoreSnapshot' and set the $Snapshot items to '$true' for the 
        data you want to restore.
        
        In case you want to restore another snapshot than the last one created
        use the '$RestoreSnapshotFolder'.

    .PARAMETER Action
        A snapshot of the current machine is created when set to 
        'CreateSnapshot'. When set to 'RestoreSnapshot' the last created 
        snapshot will be restored on the current machine.

    .PARAMETER Snapshot
        Defines for which items to create a snapshot or which items to restore.

    .PARAMETER RestoreSnapshotFolder
        By default the last created snapshot is used for restoring data. By
        using the argument '$RestoreSnapshotFolder' it is possible to restore
        data from a specific folder. This allows for the creation of named
        snapshot folders that can be restored on specific machines. 
        
        Simply copy/paste the data you want to restore to a specific folder
        and add the folder path to '$RestoreSnapshotFolder'.
#>

[CmdLetBinding()]
Param (
    [ValidateSet('CreateSnapshot' , 'RestoreSnapshot')]
    [String]$Action = 'CreateSnapshot',
    [HashTable]$Snapshot = @{
        FirewallRules = $false
        SmbShares     = $true
    },
    [String]$RestoreSnapshotFolder,
    [HashTable]$Script = @{
        FirewallRules = "$PSScriptRoot\Scripts\ImportExportFirewallRules.ps1"
        SmbShares     = "$PSScriptRoot\Scripts\ImportExportSmbShares.ps1"
    },
    [String]$SnapshotFolder = "$PSScriptRoot\Snapshots"
)

Begin {
    Function Invoke-ScriptHC {
        [CmdLetBinding()]
        Param (
            [Parameter(Mandatory)]
            [String]$Path,
            [Parameter(Mandatory)]
            [String]$DataFolder,
            [Parameter(Mandatory)]
            [ValidateSet('Export', 'Import')]
            [String]$Type
        )

        Write-Verbose "Invoke script '$Path' on data folder '$DataFolder' for '$Type'"
        & $Path -DataFolder $DataFolder -Action $Type
    }

    Try {
        $VerbosePreference = 'Continue'
        $Error.Clear()
        $Now = Get-Date

        Write-Verbose "Start action '$Action'"

        If ($Action -eq 'CreateSnapshot') {
            #region Create snapshot folder
            try {
                $joinParams = @{
                    Path        = $SnapshotFolder
                    ChildPath   = '{0} - {1}' -f 
                    $env:COMPUTERNAME, $Now.ToString('yyyyMMddHHmmssffff')
                    ErrorAction = 'Stop'
                }
                $SnapshotFolder = Join-Path @joinParams
                $null = New-Item -Path $SnapshotFolder -ItemType Directory
            }
            catch {
                Throw "Failed to created snapshot folder '$SnapshotFolder': $_"
            }
            #endregion
        }
        else {
            If ($RestoreSnapshotFolder) {
                #region Test RestoreSnapshotFolder
                If (-not (Test-Path -Path $RestoreSnapshotFolder -PathType Container)) {
                    throw "Restore snapshot folder '$RestoreSnapshotFolder' not found"
                }
                #endregion

                $SnapshotFolder = $RestoreSnapshotFolder
            }
            else {
                #region Test snapshot folder
                If (-not (Test-Path -Path $SnapshotFolder -PathType Container)) {
                    throw "Snapshot folder '$SnapshotFolder' not found. Please create your first snapshot with action 'CreateSnapshot'"
                }
                #endregion

                #region Get latest snapshot folder
                $getParams = @{
                    Path        = $SnapshotFolder
                    Directory   = $true
                    ErrorAction = 'Stop'
                }
                $SnapshotFolder = Get-ChildItem @getParams | Sort-Object LastWriteTime | 
                Select-Object -Last 1 -ExpandProperty FullName
                #endregion

                #region Test latest snapshot
                If (-not $SnapshotFolder) {
                    throw "No data found in snapshot folder '$($getParams.Path)' to restore. Please create a snapshot first with Action 'CreateSnapshot'"
                }
                #endregion
            }

            #region Test snapshot folder
            If ((Get-ChildItem -LiteralPath $SnapshotFolder | Measure-Object).Count -eq 0) {
                throw "No data found in snapshot folder '$SnapshotFolder'"
            }
            #endregion        
        }

        Write-Verbose "Snapshot folder '$SnapshotFolder'"

        #region Test scripts and data folders
        foreach ($item in $Snapshot.GetEnumerator() | 
            Where-Object { $_.Value }
        ) {
            Write-Verbose "Snapshot '$($item.Key)'"
    
            $invokeScriptParams = @{
                Path       = $Script.$($item.Key) 
                DataFolder = Join-Path -Path $SnapshotFolder -ChildPath $item.Key
            }
    
            #region Test execution script
            If (-not $invokeScriptParams.Path) {
                throw "No script found for snapshot item '$($item.Key)'"
            }
    
            If (-not (Test-Path -Path $invokeScriptParams.Path -PathType Leaf)) {
                throw "Script file '$($invokeScriptParams.Path)' not found for snapshot item '$($item.Key)'"
            }
            #endregion
    
            If ($Action -eq 'RestoreSnapshot') {
                #region Test script folder
                If (-not (Test-Path -LiteralPath $invokeScriptParams.DataFolder -PathType Container)) {
                    throw "Snapshot folder '$($invokeScriptParams.DataFolder)' not found"
                }
    
                If ((Get-ChildItem -LiteralPath $invokeScriptParams.DataFolder | Measure-Object).Count -eq 0) {
                    throw "No data found for snapshot item '$($item.Key)' in folder '$($invokeScriptParams.DataFolder)'"
                }
                #endregion
            }
        }
        #endregion
    }    
    Catch {
        throw "Failed to perform action '$Action'. Nothing done, please fix this error first: $_"
    }
}

Process {
    $childScriptTerminatingErrors = @()

    foreach ($item in $Snapshot.GetEnumerator() | Where-Object { $_.Value }) {
        Try {
            Write-Verbose "Snapshot '$($item.Key)'"

            $invokeScriptParams = @{
                Path       = $Script.$($item.Key) 
                DataFolder = Join-Path -Path $SnapshotFolder -ChildPath $item.Key
            }

            If ($Action -eq 'CreateSnapshot') {
                $null = New-Item -Path $invokeScriptParams.DataFolder -ItemType Directory

                $invokeScriptParams.Type = 'Export'
            }
            else {
                $invokeScriptParams.Type = 'Import'
            }

            Invoke-ScriptHC @invokeScriptParams
        }
        Catch {
            $childScriptTerminatingErrors += "Failed to execute script '$($invokeScriptParams.Path)' for snapshot item '$($item.Key)': $_"
            $Error.RemoveAt(0)
        }
    }
}

End {
    Try {
        Write-Verbose "End action '$Action'"
        
        $errorsFound = $false

        if ($childScriptTerminatingErrors) {
            $errorsFound = $true
            Write-Host 'Blocking errors:' -ForegroundColor Red
            $childScriptTerminatingErrors | ForEach-Object {
                Write-Host $_ -ForegroundColor Red
            }
        }
        if ($Error.Exception.Message) {
            $errorsFound = $true
            Write-Warning "Non blocking errors:"
            $Error.Exception.Message | ForEach-Object {
                Write-Warning $_
            }
        }
        if (-not $errorsFound) {
            Write-Host "$Action successful" -ForegroundColor Green
        }
    }
    Catch {
        throw "Failed to perform action '$Action': $_"
    }
}