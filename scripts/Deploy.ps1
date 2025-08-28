$param = @{
    Author            = 'Dawid Prowadzisz'
    RootModule        = 'HPDrivers.psm1'
    Path              = 'HPDrivers.psd1'
    ModuleVersion     = '2.0'
    GUID              = 'f87cbea8-7a55-47a4-b226-110750dd328d'
    Description       = 'Update all HP device drivers with a single command.'
    Copyright         = '(c) 2023 Dawid Prowadzisz. All rights reserved.'
    ProjectUri        = 'https://github.com/UsefulScripts01/HPDrivers'
    FunctionsToExport = 'Get-HPDrivers'
    CmdletsToExport   = '*'
    VariablesToExport = '*'
    AliasesToExport   = '*'
    FileList          = @(
        'HPDrivers.psm1'
        'HPDrivers.psd1'
    )
    Tags              = @(
        'HP'
        'Drivers'
        'BIOS'
        'UEFI'
        'Deployment'
    )

    ReleaseNotes      =
    '

Update all HP device drivers with a single command - Get-HPDrivers


Parameters

-NoPrompt [switch] - Download and install all drivers
-OsVersion [string] - Specify the operating system version (e.g. 22H2, 23H2)
-ShowSoftware [switch] - Show additional HP software in the driver list
-Overwrite [switch] - Install drivers even if the current driver version is the same
-BIOS [switch] - Update BIOS to the latest version
-DeleteInstallationFiles [switch] - Delete the HP SoftPaq installation files stored in .\hpdrivers\
-SuspendBL [switch] - Suspend BitLocker protection for one restart
-DownloadOnly [switch] - Download all drivers to .\hpdrivers\ , no Out-GridView select. 
-Offline [switch] - Install drivers from .\hpdrivers\ no need for internet connection. 

Examples

Example 1:
Get-HPDrivers -NoPrompt

Simple, just download and install all drivers.


Example 2:
Get-HPDrivers -ShowSoftware -DeleteInstallationFiles -SuspendBL

Show a list of available drivers and additional software. The selected drivers will be installed automatically.
Do not keep installation files. Suspend the BitLocker pin on next reboot.


Example 3:
Get-HPDrivers -NoPrompt -BIOS -Overwrite

Download and install all drivers and BIOS, even if the current driver version is the same.


Example 4:
Get-HPDrivers -OsVersion 22H2

Show a list of available drivers that match the current platform and Windows 22H2. The selected drivers will be installed automatically.


## v1.4.3
- Added search for latest drivers even if available driver version on HP servers is older than current Windows version (for older computers)
- Added HP software (e.g. dock firmware, manageability, diagnostic) to -ShowSoftware parameter
- Added max 5 driver download attempts in case of failure
- Fixed minor bugs

## v1.4.0
- First standalone version that does not use the HP CMSL module.

'
}
New-ModuleManifest @param

$ApiKey = Read-Host -Prompt "Enter API key"
Publish-Module -Path . -Repository PSGallery -NuGetApiKey $ApiKey
