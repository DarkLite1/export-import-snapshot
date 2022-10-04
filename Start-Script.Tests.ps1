#Requires -Modules Pester
#Requires -Version 5.1

BeforeAll {
    $testScript = $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    $testParams = @{
        Action              = 'CreateSnapshot'
        Snapshot            = [Ordered]@{
            Script1 = $false
            Script2 = $true
        }
        Script              = @{
            Script1 = (New-Item 'TestDrive:/1.ps1' -ItemType File).FullName
            Script2 = (New-Item 'TestDrive:/2.ps1' -ItemType File).FullName
        }
        SnapshotsFolder     = (New-Item 'TestDrive:/A' -ItemType Directory).FullName
        ReportsFolder       = (New-Item 'TestDrive:/R' -ItemType Directory).FullName
        OpenReportInBrowser = $false
    }
    $testFolder = (New-Item 'TestDrive:/B' -ItemType Directory).FullName

    Function Invoke-ScriptHC {
        Param (
            [Parameter(Mandatory)]
            [String]$Path,
            [Parameter(Mandatory)]
            [String]$DataFolder,
            [Parameter(Mandatory)]
            [ValidateSet('Export', 'Import')]
            [String]$Type
        )
    }
    Mock Invoke-ScriptHC
    Mock Restart-Computer
    Mock Write-Host
    Mock Write-Warning
    Mock Write-Progress
}
Describe "Throw a terminating error for action 'CreateSnapshot' when" {
    BeforeEach {
        $testNewParams = $testParams.clone()
        $testNewParams.Action = 'CreateSnapshot'
    }
    It 'the snapshots folder cannot be created' {
        $testNewParams.SnapshotsFolder = 'x:/xxx'
        { .$testScript @testNewParams } | 
        Should -Throw "*Snapshots folder 'x:/xxx' not found*"
    }
    It 'the script does not exist' {
        $testNewParams.Snapshot = [Ordered]@{
            Script1 = $true
        }
        $testNewParams.Script = @{
            Script1 = 'TestDrive:/xxx.ps1'
        }
        { .$testScript @testNewParams } | 
        Should -Throw "*Script file 'TestDrive:/xxx.ps1' not found for snapshot item 'Script1'"
    }
    It 'a snapshot is requested for an item that does not exist' {
        $testNewParams.Snapshot = [Ordered]@{
            Unknown = $true
        }
        { .$testScript @testNewParams } | 
        Should -Throw "*No script found for snapshot item 'Unknown'"
    }
}
Describe "Throw a terminating error for action 'RestoreSnapshot' when" {
    BeforeEach {
        $testNewParams = $testParams.clone()
        $testNewParams.Action = 'RestoreSnapshot'
        $testNewParams.RestoreSnapshotFolder = $testFolder
    }
    It "The parameter 'RestoreSnapshotFolder' is missing" {
        $testNewParams.Remove('RestoreSnapshotFolder')

        { .$testScript @testNewParams } | 
        Should -Throw "*The parameter 'RestoreSnapshotFolder' is mandatory. Please specify the folder containing the snapshot data that needs to be restored on the current computer*"
    }
    It "the 'RestoreSnapshotFolder' is not found'" {
        $testNewParams.RestoreSnapshotFolder = 'TestDrive:/xxx'

        { .$testScript @testNewParams } | 
        Should -Throw "*Restore snapshot folder 'TestDrive:/xxx' not found"
    }
    It "the 'RestoreSnapshotFolder' is empty" {
        { .$testScript @testNewParams } | 
        Should -Throw "*No data found in snapshot folder '$($testNewParams.RestoreSnapshotFolder)'"
    }
    It "the script restore folder is not found" {
        New-Item "$testFolder/a" -ItemType Directory
        $testScriptFolder = Join-Path $testFolder 'Script2'

        { .$testScript @testNewParams } | 
        Should -Throw "*Restore folder '$testScriptFolder' for snapshot item 'Script2' not found"
    }
    It "the script restore folder is empty" {
        $testScriptFolder = New-Item "$testFolder\Script2" -ItemType Directory

        { .$testScript @testNewParams } | 
        Should -Throw "*Restore folder '$testScriptFolder' for snapshot item 'Script2' is empty"
    }
    It 'the script does not exist' {
        $testNewParams.Snapshot = [Ordered]@{
            Script1 = $true
        }
        $testNewParams.Script = @{
            Script1 = 'TestDrive:/xxx.ps1'
        }
        
        { .$testScript @testNewParams } | 
        Should -Throw "*Script file 'TestDrive:/xxx.ps1' not found for snapshot item 'Script1'"
    } 
    It 'the json file could not be imported' {
        $testFile = "$testFolder\Script2\export.json"
        'a' | Out-File -LiteralPath $testFile
        
        { .$testScript @testNewParams } | 
        Should -Throw "*File '$testFile' is not a valid json file for snapshot item 'Script2'"
    }
}
Describe "When action is 'CreateSnapshot'" {
    BeforeAll {
        $testNewParams = $testParams.clone()
        $testNewParams.Action = 'CreateSnapshot'
        $testNewParams.Snapshot = [Ordered]@{
            Script1 = $false
            Script2 = $true
        }
        .$testScript @testNewParams
    }
    It 'a script is called for enabled snapshot items only' {
        Should -Invoke Invoke-ScriptHC -Exactly -Times 1 -Scope Describe
        Should -Invoke Invoke-ScriptHC -Exactly -Times 1 -Scope Describe -ParameterFilter {
            ($Path -eq $testNewParams.Script.Script2) -and
            ($DataFolder -like '*Script2*') -and
            ($Type -eq 'Export')
        }
        Should -Not -Invoke Invoke-ScriptHC -Scope Describe -ParameterFilter {
            ($Path -eq $testNewParams.Script.Script1)
        }
    }
}
Describe "When action is 'RestoreSnapshot' and 'RestoreSnapshotFolder' is set" {
    BeforeAll {
        $testNewParams = $testParams.clone()
        $testNewParams.Action = 'RestoreSnapshot'
        $testNewParams.RestoreSnapshotFolder = $testFolder
        $testNewParams.RebootComputerAfterRestoreSnapshot = $true
        $testNewParams.Snapshot = [Ordered]@{
            Script1 = $false
            Script2 = $true
        }

        $testScriptFolder = (New-Item "$testFolder\Script2" -ItemType Directory).FullName
        New-Item "$testScriptFolder\Export.csv" -ItemType file

        .$testScript @testNewParams
    }
    It 'a script is called for enabled snapshot items only' {
        Should -Invoke Invoke-ScriptHC -Exactly -Times 1 -Scope Describe
        Should -Invoke Invoke-ScriptHC -Exactly -Times 1 -Scope Describe -ParameterFilter {
            ($Path -eq $testNewParams.Script.Script2) -and
            ($DataFolder -eq $testScriptFolder) -and
            ($Type -eq 'Import')
        }
    } 
    It 'restart the computer when using RebootComputerAfterRestoreSnapshot' {
        Should -Invoke Restart-Computer -Exactly -Times 1 -Scope Describe
    }
    Context "the 'RestoreSnapshotFolder' can be" {
        BeforeAll {
            $testRelativeRestoreFolder = "$PSScriptRoot\test"
            $testScriptFolder = (New-Item "$testRelativeRestoreFolder\Script2" -ItemType Directory).FullName
            New-Item "$testScriptFolder\Export.csv" -ItemType file
        }
        AfterAll {
            Remove-Item $testRelativeRestoreFolder -Recurse
        }
        It 'a relative path' {
            $testNewParams.RestoreSnapshotFolder = '.\test'

            .$testScript @testNewParams
    
            Should -Invoke Restart-Computer -Exactly -Times 1
        }
    }
} -Tag test
Describe 'Other scripts are still executed when' {
    BeforeAll {
        Get-ChildItem -Path 'TestDrive:/' -Filter '*.ps1' |
        Remove-Item
    
        $testNewParams = $testParams.clone()
        $testNewParams.Action = 'CreateSnapshot'
        $testNewParams.Snapshot = [Ordered]@{
            Script1 = $true
            Script2 = $true
            Script3 = $true
        }
        $testNewParams.Script = @{
            Script1 = (New-Item 'TestDrive:/1.ps1' -ItemType File).FullName
            Script2 = (New-Item 'TestDrive:/2.ps1' -ItemType File).FullName
            Script3 = (New-Item 'TestDrive:/3.ps1' -ItemType File).FullName
        }
    }
    It 'a child script fails with a non terminating error' {
        Mock Invoke-ScriptHC {
            Write-Error 'Script2 non terminating error'
        } -ParameterFilter { $Path -eq $testNewParams.Script.Script2 }

        .$testScript @testNewParams -ErrorAction SilentlyContinue

        Should -Invoke Invoke-ScriptHC -Times 3 -Exactly
        Should -Invoke Invoke-ScriptHC -Times 1 -Exactly -ParameterFilter { 
            $Path -eq $testNewParams.Script.Script1 
        }
        Should -Invoke Invoke-ScriptHC -Times 1 -Exactly -ParameterFilter { 
            $Path -eq $testNewParams.Script.Script2 
        }
        Should -Invoke Invoke-ScriptHC -Times 1 -Exactly -ParameterFilter { 
            $Path -eq $testNewParams.Script.Script3 
        }
    }
    It 'a child script fails with a terminating error' {
        Mock Invoke-ScriptHC {
            throw 'Script2 terminating error'
        } -ParameterFilter { $Path -eq $testNewParams.Script.Script2 }

        .$testScript @testNewParams

        Should -Invoke Invoke-ScriptHC -Times 3 -Exactly
        Should -Invoke Invoke-ScriptHC -Times 1 -Exactly -ParameterFilter { 
            $Path -eq $testNewParams.Script.Script1 
        }
        Should -Invoke Invoke-ScriptHC -Times 1 -Exactly -ParameterFilter { 
            $Path -eq $testNewParams.Script.Script2 
        }
        Should -Invoke Invoke-ScriptHC -Times 1 -Exactly -ParameterFilter { 
            $Path -eq $testNewParams.Script.Script3 
        }
    }
}
Describe 'When child scripts are executed' {
    BeforeAll {
        Get-ChildItem -Path 'TestDrive:/' -Filter '*.ps1' |
        Remove-Item
    
        $testNewParams = $testParams.clone()
        $testNewParams.Action = 'CreateSnapshot'
        $testNewParams.Snapshot = [Ordered]@{
            Script1 = $true
            Script2 = $true
            Script3 = $true
        }
        $testNewParams.Script = @{
            Script1 = (New-Item 'TestDrive:/1.ps1' -ItemType File).FullName
            Script2 = (New-Item 'TestDrive:/2.ps1' -ItemType File).FullName
            Script3 = (New-Item 'TestDrive:/3.ps1' -ItemType File).FullName
        }
        $testNewParams.ReportsFolder = 'TestDrive:/R2'

        Mock Invoke-ScriptHC {
            throw 'Script1 terminating error'
        } -ParameterFilter { $Path -eq $testNewParams.Script.Script1 }
        Mock Invoke-ScriptHC {
            Write-Error 'Script2 non terminating error'
        } -ParameterFilter { $Path -eq $testNewParams.Script.Script2 }
        Mock Invoke-ScriptHC {
            'normal output1'
            'normal output2'
            'normal output3'
        } -ParameterFilter { $Path -eq $testNewParams.Script.Script3 }

        .$testScript @testNewParams -EA SilentlyContinue

        $testGetParams = @{
            Path        = $testNewParams.ReportsFolder 
            Filter      = '*.html'
            ErrorAction = 'Ignore'
        }
        If ($testReportFile = (Get-ChildItem @testGetParams).FullName) {
            $testReport = Get-Content $testReportFile
        }
    }
    It 'a report folder is created' {
        $testNewParams.ReportsFolder | Should -Exist
    }
    It 'an HTML file is created' {
        $testReportFile | Should -Exist
    }
    It 'terminating errors are reported' {
        $testReport | Where-Object { $_ -like '*Blocking error*' } | 
        Should -Not -BeNullOrEmpty
        $testReport | Where-Object { $_ -like '*Script1 terminating error*' } | 
        Should -Not -BeNullOrEmpty
    }
    It 'non terminating errors are reported' {
        $testReport | Where-Object { $_ -like '*Non blocking errors*' } | 
        Should -Not -BeNullOrEmpty
        $testReport | Where-Object { 
            $_ -like '*Script2 non terminating error*' 
        } | 
        Should -Not -BeNullOrEmpty
    }
    It 'output is reported' {
        $testReport | Where-Object { $_ -like '*Non blocking errors*' } | 
        Should -Not -BeNullOrEmpty
        $testReport | Where-Object { $_ -like '*normal output1*' } | 
        Should -Not -BeNullOrEmpty
        $testReport | Where-Object { $_ -like '*normal output2*' } | 
        Should -Not -BeNullOrEmpty
        $testReport | Where-Object { $_ -like '*normal output3*' } | 
        Should -Not -BeNullOrEmpty
    }
}