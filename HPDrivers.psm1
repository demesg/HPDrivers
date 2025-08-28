function ShowHPDriversStatus ([Parameter(Mandatory = $false)] [string]$Status) {
    <#
    .SYNOPSIS
        Displays the status of the installed driver, including its ID, name, and version.

    .DESCRIPTION
        The ShowHPDriversStatus function creates a custom object with properties Id, Name, Version, and Status.
        It then selects and displays these properties.

    .PARAMETER Status
        An optional string parameter that specifies the status of the object.
        If not provided, the default value is $null.

    .EXAMPLE
        ShowHPDriversStatus -Status "Installed"
        This command will display the status as "Active" along with the Id, Name, and Version of the object.
    #>

    $Info = New-Object -Type PSObject -Property @{
        'Id'      = $Number
        'Name'    = $Name
        'Version' = $AvailableSpVersion
        'Status'  = $Status
    }
    $Info | Select-Object -Property Id, Name, Version, Status
}


function WriteToHPDriversLog ([Parameter(Mandatory = $false)] [string]$Status) {
    <#
    .SYNOPSIS
        Collect HPDrivers module logs.

    .DESCRIPTION
        'WriteToHPDriversLog' collects log files regarding installations and errors.
        This function will be called multiple times in the script below.
    #>

    $TimeStamp = (Get-Date).ToString("[yyy-MM-dd HH:mm:sss]")
    $LogMessage = $TimeStamp + ' - ' + $Number + ' - ' + $Status + ' - ' + $AvailableSpVersion + ' - ' + $Name
    $LogMessage | Out-File -FilePath "$PWD\HPDrivers\InstalledHPDrivers.log" -Append

    # Collect occurred errors
    foreach ($Entry in $Error) {
        $ErrorMessage = $TimeStamp + ' - ' + $Entry
        $ErrorMessage | Out-File -FilePath "$PWD\HPDrivers\HPDriversError.log" -Append
    }
    $Error.Clear()
}


function Get-HPDrivers {
    <#
    .SYNOPSIS
        Update all HP device drivers with a single command - Get-HPDrivers.

    .DESCRIPTION
        The HPDrivers module downloads and installs softpaqs that match the operating system version and hardware configuration.
        Can run in offline mode and caches previous downloaded drivers.

    .PARAMETER NoPrompt
        Download and install all drivers.

    .PARAMETER OsVersion
        Specify the operating system version (e.g. 22H2, 23H2).

    .PARAMETER ShowSoftware
        Show additional HP software in the driver list.

    .PARAMETER Overwrite
        Install the drivers even if the current driver version is the same.

    .PARAMETER BIOS
        Update the BIOS to the latest version.

    .PARAMETER DeleteInstallationFiles
        Delete the HP SoftPaq installation files stored in $PWD\HPDrivers.

    .PARAMETER SuspendBL
        Suspend BitLocker protection for one restart.
    
    .PARAMETER Offline
        Use cached downloads, no need for Internet.
    
    .PARAMETER DownloadOnly
        Skip driver install.

    .LINK
        https://github.com/demesg/HPDrivers

    .LINK
        https://www.powershellgallery.com/packages/HPDrivers

    .EXAMPLE
        Get-HPDrivers -NoPrompt

        Simple, just download and install all drivers.

    .EXAMPLE
        Get-HPDrivers -ShowSoftware -DeleteInstallationFiles -SuspendBL

        Show a list of available drivers and additional software. The selected drivers will be installed automatically. Do not keep installation files. Suspend the BitLocker pin on next reboot.

    .EXAMPLE
        Get-HPDrivers -NoPrompt -BIOS -Overwrite

        Download and install all drivers and BIOS, even if the current driver version is the same.

    .EXAMPLE
        Get-HPDrivers -OsVersion '22H2'

        Show a list of available drivers that match the current platform and Windows 22H2. The selected drivers will be installed automatically.

    .EXAMPLE
        Get-HPDrivers -DownloadOnly -NoPrompt

        Download all drivers to .\hpdrivers\ , no Out-GridView select. 
    
    .EXAMPLE
        Get-HPDrivers -offline

        Install selected drivers from local cache in .\hpdrivers\ . 

    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [switch]$NoPrompt,
        [Parameter(Mandatory = $false)] [string]$OsVersion,
        [Parameter(Mandatory = $false)] [switch]$ShowSoftware,
        [Parameter(Mandatory = $false)] [switch]$Overwrite,
        [Parameter(Mandatory = $false)] [switch]$BIOS,
        [Parameter(Mandatory = $false)] [switch]$DeleteInstallationFiles,
        [Parameter(Mandatory = $false)] [switch]$SuspendBL,
        [Parameter(Mandatory = $false)] [switch]$Offline,
        [Parameter(Mandatory = $false)] [switch]$DownloadOnly
    )

    $ProgressPreference = 'Continue'
    $Error.Clear()
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Classes and informations needed for further use
    # collect information about the current machine
    $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
    $BaseBoard = Get-CimInstance -ClassName Win32_BaseBoard

    if ($OperatingSystem.Caption -match "10") { $OsType = "10" }
    if ($OperatingSystem.Caption -match "11") { $OsType = "11" }

    $OsVer = (Get-Item "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion").GetValue('DisplayVersion')
    [Int32]$Year = $OsVer.Split('H')[0]
    [Int32]$Half = $OsVer.Split('H')[1]

    # if machine manufacturer is HP
    if (($ComputerSystem.Manufacturer -match "HP") -or ($ComputerSystem.Manufacturer -match "Hewlett-Packard")) {

        # test connectio with hpia.hpcloud.hp.com
        $TestConn = Test-Connection "hpia.hpcloud.hp.com" -Count 2 -ErrorAction Ignore
        if (!$TestConn -and !$Offline) {
            Write-Output `n
            Write-Warning "hpia.hpcloud.hp.com is unavailable!`nPlease check your internet connection or try again later..`n"
            Break
        }

        # warn if battery charge drops below 50%
        $Charge = (Get-CimInstance -ClassName Win32_Battery).EstimatedChargeRemaining
        if ($Charge -le "50") {
            Write-Output `n
            Write-Warning "Battery level: ${Charge}%`nPLEASE CONNECT AN AC ADAPTER`n"
        }

        # create the path
        if (!(Test-Path -Path "$PWD\HPDrivers")) {
            New-Item -ItemType Directory -Path "$PWD\HPDrivers" -Force
        }
        #Set-Location -Path "$PWD\HPDrivers"

        # Remove the old files
        #Get-ChildItem -Path "$PWD\HPDrivers\*.xml" | Remove-Item
        #Get-ChildItem -Path "$PWD\HPDrivers\*.cab" | Remove-Item

        # Download the CAB file containing the XML list of drivers that match your current machine
        if (!$OsVersion) {
            while (!(Test-Path -Path "$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVer}.xml")) {
                try {
                    $CabUri = ("https://hpia.hpcloud.hp.com/ref/$($BaseBoard.Product)/$($BaseBoard.Product)_64_${OsType}.0.${OsVer}.cab").ToLower()
                    $WebClient = New-Object -TypeName System.Net.WebClient
                    $WebClient.DownloadFile($CabUri, "$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVer}.cab")

                    Invoke-Expression -Command "expand '$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVer}.cab' '$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVer}.xml'" | Out-Null
                    
                    Write-Output `n
                    Write-Verbose "Latest drivers found: $($ComputerSystem.Model) - Windows $($OsVer.ToUpper()).." -Verbose
                    "$($ComputerSystem.Model) - $($BaseBoard.Product)_64_${OsType}.0.${OsVer}" | Out-File -FilePath "$PWD\HPDrivers\Models.txt" -Append
                }
                catch {
                    # Try to set the previous version
                    if ($Half.Equals(2)) {
                        $Half = 1
                    }
                    else {
                        $Year -= 1
                        $Half = 2
                    }
                    $OsVer = "$Year" + 'H' + "$Half"

                    # Exit if the drivers version is older than 2020y
                    if ($Year -lt 20) {
                        Write-Warning "Could not find drivers that match your model ($($ComputerSystem.Model)) - Windows $($OsVer.ToUpper()).."
                        Break
                    }
                }
            }
        }elseif ($Offline){
                Write-Verbose "Offline mode.." -Verbose
        }

        # If the operating system version is defined in the parameter
        if ($OsVersion) {
            try {
                $CabUri = ("https://hpia.hpcloud.hp.com/ref/$($BaseBoard.Product)/$($BaseBoard.Product)_64_${OsType}.0.${OsVersion}.cab").ToLower()
                $WebClient = New-Object -TypeName System.Net.WebClient
                    $WebClient.DownloadFile($CabUri, "$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVersion}.cab")

                    Invoke-Expression -Command "expand '$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVersion}.cab' '$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVersion}.xml'" | Out-Null

                Write-Output `n
                Write-Verbose "Latest drivers found: $($ComputerSystem.Model) - Windows $($OsVersion.ToUpper()).." -Verbose
                "$($ComputerSystem.Model) - $($BaseBoard.Product)_64_${OsType}.0.${OsVer}" | Out-File -FilePath "$PWD\HPDrivers\Models.txt" -Append

            }
            catch {
                Write-Warning "Could not find drivers that match your model ($($ComputerSystem.Model)) - Windows $($OsVersion.ToUpper()).."
                Break
            }
        }elseif ($Offline){
                Write-Verbose "Offline mode.." -Verbose
        }
        
        if (Test-Path -Path "$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVer}.xml") {
            [XML]$Script:XML = Get-Content -Path "$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVer}.xml"
            Write-Verbose "$($ComputerSystem.Model) uses definition file: $($BaseBoard.Product)_64_${OsType}.0.${OsVer}.xml" -Verbose
        }else{
            Write-Warning "Could not find local definition file ($($BaseBoard.Product)_64_${OsType}.0.${OsVer}.xml) that match your model ($($ComputerSystem.Model))"
        }


        # Remove the old files
        #Get-ChildItem -Path "$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVersion}.xml" | Remove-Item
        #Get-ChildItem -Path "$PWD\HPDrivers\$($BaseBoard.Product)_64_${OsType}.0.${OsVersion}.cab" | Remove-Item

        # Sort the driver list
        # 'Driverpack' = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'Driverpack' }
        # 'UWPPack' = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'UWPPack' }
        $Category = New-Object -Type PSObject @{
            'Driver'        = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'Driver -' }
            'Diagnostic'    = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'Diagnostic' }
            'Utility'       = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'Utility -' }
            'Dock'          = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'Dock -' }
            'Software'      = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'Software -' }
            'Firmware'      = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'Firmware' }
            'Manageability' = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'Manageability -' }
            'BIOS'          = $Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Category -match 'BIOS' }
        }

        # Select driver category
        $AvailableDrivers = $Category.Driver

        # -ShowSoftware
        if ($ShowSoftware) {
            $AvailableDrivers += $Category.Diagnostic
            $AvailableDrivers += $Category.Utility
            $AvailableDrivers += $Category.Dock
            $AvailableDrivers += $Category.Software
            $AvailableDrivers += $Category.Firmware
            $AvailableDrivers += $Category.Manageability
        }

        # -Bios
        if ($BIOS) {
            $AvailableDrivers += $Category.BIOS
        }

        # Select drivers from the list of available drivers
        if (!$NoPrompt) {
            $SpList = $AvailableDrivers | Select-Object -Property id, Name, Category, Version, Size, DateReleased | Out-GridView -Title "Select driver(s):" -OutputMode Multiple
        }

        # Select all drivers without prompt
        # -NoPrompt
        if ($NoPrompt) {
            $SpList = $AvailableDrivers
        }

        # Insert a line to the log file
        $Date = Get-Date -Format "yyyy-MM-dd"
        $HR = "-" * 100
        $Line = "[$Date]" + " " + $HR
        $Line | Out-File -FilePath "$PWD\HPDrivers\InstalledHPDrivers.log" -Append

        # Show list of available drivers
        if ($SpList) {
            Write-Verbose "The script will process the following drivers. Please wait..`n" -Verbose
            $SpList | Select-Object -Property Id, Name, Version, Size, DateReleased | Format-Table -AutoSize
        }
        if ($BadLinks) {
            Write-Warning "The following drivers are not available on the HP server `n"
            $BadLinks | Select-Object -Property Id, Name, Version, Size, DateReleased | Format-Table -AutoSize
        }

        # download and install selected drivers
        foreach ($Number in $SpList.id) {

            # Obtain information about the actual installed driver
            $Script:Name = ($Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Id -eq $Number }).Name
            $Script:Source = ($Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Id -eq $Number }).Url
            $Script:SilentInstall = ($Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Id -eq $Number }).SilentInstall
            $Script:AvailableSpVersion = ($Xml.ImagePal.Solutions.UpdateInfo | Where-Object { $_.Id -eq $Number }).Version

            # Get the version of the installed softpaq package
            $InstalledSpVersion = 0

            if (!$Overwrite) {
                $CvaFile = Get-ChildItem -Path "C:\SWSetup\$Number" -Filter "*.cva" -Recurse -ErrorAction Ignore
                if ($CvaFile) {
                    $CvaContent = Get-Content -Path $CvaFile.VersionInfo.FileName
                    $InstalledSpVersion = ($CvaContent | Select-String -Pattern "^VendorVersion").ToString().Split('=')[1]
                }

                if (Test-Path -Path "C:\SWSetup\$Number\version.txt") {
                    $InstalledSpVersion = Get-Content -Path "C:\SWSetup\$Number\version.txt" -ErrorAction SilentlyContinue
                }
            }

            # if a new driver version is available
            if ($AvailableSpVersion -gt $InstalledSpVersion) {

                try {
                    # Download a softpaq (5 attempts)
                    $Count = 1
                    while (!(Test-Path -Path "$PWD\HPDrivers\${Number}.exe") -and ($Count -le 5)) {
                        Get-BitsTransfer | Remove-BitsTransfer
                        Start-BitsTransfer -Source "https://${Source}" -Destination "$PWD\HPDrivers" -DisplayName "Downloading (attempt ${Count}/5):" -Description $Name -Dynamic -ErrorAction Ignore
                        $Count += 1
                    }

                    # Checksum
                    $SPFileExist = Test-Path -Path "$PWD\HPDrivers\${Number}.exe"
                    $SPFileChecksum = (Get-FileHash -Path "$PWD\HPDrivers\${Number}.exe" -Algorithm SHA256).Hash
                    $OryginalChecksum = ($AvailableDrivers | Where-Object { $_.Id -eq $Number }).SHA256

                    # Checksum is OK
                    if ($SPFileExist -or ($SPFileChecksum -eq $OryginalChecksum)) {
                        # Only Download
                        if ($DownloadOnly){
                            Write-Verbose "Downloaded: 'https://${Source}' to '.\HPDrivers\${Number}.exe'`n" -Verbose     
                            Continue                  
                        }

                        # Installation process
                        $SetupFile = $SilentInstall.Split()[0].Trim('"')
                        $SetupCommand = $SilentInstall.Split()[0]
                        $Param = $SilentInstall.Replace($SetupCommand, '')

                        # Setup.exe files with a special params
                        if ($Param) {
                            Start-Process -FilePath "$PWD\HpDrivers\$Number" -Wait -ArgumentList "/s /e /f C:\SWSetup\$Number"
                            Start-Process -FilePath "C:\SWSetup\$Number\$SetupFile" -Wait -ArgumentList $Param
                        }

                        # CMD Wrapper, HPUP and other installers
                        if (!$Param) {
                            Start-Process -FilePath "$PWD\HpDrivers\${Number}.exe" -Wait -ArgumentList "/s /f C:\SWSetup\$Number"
                        }

                        # Save file with installd version
                        if (Test-Path -Path "C:\SWSetup\$Number") {
                            $AvailableSpVersion | Out-File -FilePath "C:\SWSetup\$Number\version.txt"
                        }

                        ShowHPDriversStatus -Status "Installed"
                        WriteToHPDriversLog -Status "Installed"
                        Start-Sleep -Seconds 2
                    }

                    else {
                        ShowHPDriversStatus -Status "Failed!"
                        WriteToHPDriversLog -Status "Failed!"
                    }
                }

                catch {
                    ShowHPDriversStatus -Status "Failed!"
                    WriteToHPDriversLog -Status "Failed!"
                }

                # remove installation files
                if ($DeleteInstallationFiles -and (Test-Path -Path "$PWD\HPDrivers")) {
                    Get-ChildItem -Path "$PWD\HPDrivers\${Number}.exe" | Remove-Item -Force
                }
            }

            if ($DownloadOnly){
                Continue                  
            }

            # if the driver is up to date
            if ($AvailableSpVersion -le $InstalledSpVersion) {

                # Save file with installd version
                if (Test-Path -Path "C:\SWSetup\$Number") {
                    $AvailableSpVersion | Out-File -FilePath "C:\SWSetup\$Number\version.txt"
                }

                ShowHPDriversStatus -Status "Already Installed"
                WriteToHPDriversLog -Status "Already Installed"
            }
        }

        # disable BitLocker pin for one restart (BIOS update)
        if ($SuspendBL -and ((Get-BitLockerVolume -MountPoint "C:").VolumeStatus -ne "FullyDecrypted")) {
            Suspend-BitLocker -MountPoint "C:" -RebootCount 1
        }

        # remove installation files
        if ($DeleteInstallationFiles -and (Test-Path -Path "$PWD\HPDrivers")) {
            Get-ChildItem -Path "$PWD\HPDrivers" -Filter "*.exe" | Remove-Item -Force
        }
    }
}
Export-ModuleMember -Function Get-HPDrivers
