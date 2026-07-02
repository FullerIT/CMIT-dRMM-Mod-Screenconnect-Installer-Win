<#
Script:        CMIT-dRMM-Mod-Screenconnect-Installer-Win.ps1
Author:        pellis@cmitsolutions.com
Version:       2026.07.02.002

Change Log:
  2026.07.02.003 - Fixing createJoinLink logic
  2026.07.02.002 - Fixing the UDF Field Entry and device type stdout
  2026.07.02.001 - First version

.SYNOPSIS
    Modified version of Datto's ConnectWise ScreenConnect (Control) [WIN] to include options for Company, Site, Department, Device Type fields
.DESCRIPTION
    Only the 'Adding Extra URL Fields' section was added
    Custom Fields:
    usrSiteField
    usrDept
    usrDeviceType

Original Script comments below:

 IF YOU ARE EDITING THIS COMPONENT TO ADJUST THE DIGITAL SIGNATURE, PLEASE SCROLL DOWN TO THE NEXT COMMENT BLOCK (line ~90).

   connectwise screenconnect integration component :: build 8, july 2025
   script variables: ConnectWiseControlPublicKeyThumbprint/str :: ConnectWiseControlBaseUrl/str :: ConnectWiseControlInstallerUrl/str :: usrUDF/sel

   this script is the combined property of kaseya and connectwise and is used to facilitate an integration between the two companies' products.
   copyright remains with connectwise, inc; the script's contents thus must not be shared externally.
   the main body of the script was authored by seagull.
   	
   the moment you edit this script it becomes your own risk and support will not provide assistance with it.#>

write-host "ScreenConnect Integration"
write-host "==================================="

#region Functions & variables -----------------------------------------------------------------------------------------------------

[int]$script:varFail=0

function verifyPackage ($file, $certificate, $thumbprint, $name, $url) { #verifyPackage build 4x/seagull :: datto/kaseya :: BESPOKE
    if (!(test-path "$file")) {
        write-host "! ERROR: Downloaded file could not be found."
        write-host "  Please ensure firewall access to $url."
        exit 1
    }

    #construct chain
    $varChain=New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
    try {
        $varChain.Build((Get-AuthenticodeSignature -FilePath "$file").SignerCertificate) | out-null
    } catch [System.Management.Automation.MethodInvocationException] {
        write-host "! ERROR: $name installer did not contain a valid digital certificate."
        write-host "  This could suggest a change in the way $name is packaged; it could"
        write-host "  also suggest tampering in the connection chain."
        write-host "- Please ensure $url is whitelisted and try again."
        write-host "  If this issue persists across different devices, please file a support ticket."
        $script:varFail++
        return
    }

    #check digsig status
    if ((Get-AuthenticodeSignature "$file").status.value__ -ne 0) {
        write-host "! ERROR: $name installer contained a digital signature, but it was invalid."
        write-host "  This strongly suggests that the file has been tampered with."
        write-host "  Please re-attempt download. If the issue persists, contact Support."
        $script:varFail++
        return
    }

    #inspect certificate thumbprints
    $varIntermediate=($varChain.ChainElements | % {$_.Certificate} | ? {$_.Subject -match "$certificate"}).Thumbprint
    if ($varIntermediate -ne $thumbprint) {
        write-host "! ERROR: $file did not return the expected data for its digital signature."
        $script:varFail++
        return
    } else {
        write-host ": Digital Signature verification passed."
    }
}

function createJoinLink {
    try {
        $ServiceRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\ScreenConnect Client ($env:ConnectWiseControlPublicKeyThumbprint)"
        $CentraStagePath = "HKLM:\Software\CentraStage"

        Write-Host "- ScreenConnect service registry path:"
        Write-Host "  $ServiceRegPath"

        if (!(Test-Path $ServiceRegPath)) {
            Write-Host "! ERROR: ScreenConnect service registry path was not found."
            Write-Host "  Expected path: $ServiceRegPath"
            exit 1
        }

        $ImagePath = (Get-ItemProperty -Path $ServiceRegPath -Name ImagePath).ImagePath

        Write-Host "- ScreenConnect ImagePath:"
        Write-Host "  $ImagePath"

        $SessionMatch = [regex]::Match($ImagePath, '(?:\?|&)s=([a-f0-9\-]{36})', 'IgnoreCase')

        if (!$SessionMatch.Success) {
            Write-Host "! ERROR: Unable to locate ScreenConnect session GUID in ImagePath."
            Write-Host "  Expected to find a parameter like: &s=<guid>"
            exit 1
        }

        $GUID = $SessionMatch.Groups[1].Value

        Write-Host "- ScreenConnect session GUID detected:"
        Write-Host "  $GUID"

        $apiLaunchUrl = "$($env:ConnectWiseControlBaseUrl)Host#Access///$GUID/Join"

        Write-Host "- ScreenConnect join URL:"
        Write-Host "  $apiLaunchUrl"

        if ([string]::IsNullOrWhiteSpace($env:usrUDF)) {
            Write-Host "! ERROR: usrUDF is blank. Cannot determine which Datto UDF to write."
            exit 1
        }

        if (!(Test-Path $CentraStagePath)) {
            Write-Host "- CentraStage registry path not found. Creating it."
            New-Item -Path $CentraStagePath -Force | Out-Null
        }

        Set-ItemProperty `
            -Path $CentraStagePath `
            -Name "Custom$env:usrUDF" `
            -Value $apiLaunchUrl `
            -Force

        Write-Host "- UDF written to UDF#$env:usrUDF."

        $WrittenValue = (Get-ItemProperty -Path $CentraStagePath -Name "Custom$env:usrUDF")."Custom$env:usrUDF"

        Write-Host "- Confirmed UDF registry value:"
        Write-Host "  $WrittenValue"

    } catch {
        Write-Host "! ERROR: Unable to create a join link to ScreenConnect instance."
        Write-Host "  Please ensure all Component variables are furnished correctly."
        Write-Host ""
        Write-Host ": Error details:"
        $error | Select-Object *
        exit 1
    }
}

#RMM-20005 :: feb 2024
'26','61','6D','70','3B' | % {
    $varString += $([Convert]::ToChar([int][Convert]::ToInt32($_, 16)))
}
$env:ConnectWiseControlInstallerUrl = $env:ConnectWiseControlInstallerUrl -replace $varString,'&'

#region Adding Extra URL Fields --------------------------------------------------------------------------------------------------------
# Populate ScreenConnect custom properties

$Company    = [System.Uri]::EscapeDataString($env:CS_PROFILE_NAME)
$Site       = [System.Uri]::EscapeDataString($env:usrSiteField)
$Department = [System.Uri]::EscapeDataString($env:usrDept)
$DeviceType = [System.Uri]::EscapeDataString($env:usrDeviceType)

# Append ScreenConnect custom fields in order
$env:ConnectWiseControlInstallerUrl += `
    "&c=$Company" + `
    "&c=$Site" + `
    "&c=$Department" + `
    "&c=$DeviceType"

write-host "- Company: $($env:CS_PROFILE_NAME)"
write-host "- Site: $($env:usrSiteField)"
write-host "- Department: $($env:usrDept)"
write-host "- Device Type: $($env:usrDeviceType)"
write-host "- Final Installer URL:"
write-host "  $env:ConnectWiseControlInstallerUrl"

#region Installation check --------------------------------------------------------------------------------------------------------

if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\ScreenConnect Client ($env:ConnectWiseControlPublicKeyThumbprint)" ) {
    write-host "- ScreenConnect is already installed."
    write-host "  Establishing link..."
    createJoinLink
    exit
}

#region Download installer --------------------------------------------------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Enum]::ToObject([Net.SecurityProtocolType], 3072)
write-host "- Downloading installer from URL:"
write-host "  $env:ConnectWiseControlInstallerUrl"
(New-Object System.Net.WebClient).DownloadFile("$env:ConnectWiseControlInstallerUrl","ScreenConnect.ClientSetup.exe")

#region Validate installer --------------------------------------------------------------------------------------------------------

<#
    ATTENTION: If you are using an edited copy of the Component and wish to change the certificate signing credentials, this is where you need to look.
    You will need to get the URL for an EXE installer from your own ScreenConnect deployment and then pass it to the ComStore Component named
    "Download/Verify + Install File/EXE/MSI by URL [WIN]" with instructions to download, but not to execute. This Component will download your ScreenConnect
    installer and display the digital certificates against which it was signed, which you can use to adjust this verification check so the two agree.
    From that Component's output you will see a list of certificates, usually three, attached to the installer; take note of the listing in the middle.
    
    It is imperative that the downloaded file is validated before it is executed, as Datto RMM runs scripts on the endpoint as the "SYSTEM" user.
    If your infrastructure were to be compromised, a man-in-the-middle attack where expected remote files are replaced or redirected could be disastrous.
    RMMs are an increasingly common point of attack for bad actors. Please do not just comment the validation subroutine out; it may save your business.

    You will edit the command below. The first argument defines the name of the file which was downloaded in the previous command, so that can stay the same.
    The next argument defines the Subject of the digital certificate. Use the part of the subject which starts with "CN=" and ends with a comma.
    The next part is the thumbprint. That can be copied verbatim. The last two arguments are used to provide informative output if a validation error occurs.

    It should go without saying, but by editing a ComStore Component you make it your own property and you absolve Datto RMM Support of responsibility for it.
    If your duplicated, adjusted Component does not cooperate with your installer, Support will not be able to do much beyond re-word this dialogue for you.
    This Component was not written with support for the MSI installer and none is planned by ConnectWise; please use the EXE installer only.
        - seagull, July 2025
#>

verifyPackage "ScreenConnect.ClientSetup.exe" "DigiCert Trusted G4 Code Signing RSA4096 SHA384 2021 CA1" "7B0F360B775F76C94A12CA48445AA2D2A875701C" "ScreenConnect Client Setup" $env:ConnectWiseControlInstallerUrl
#------------ filename ---------------------- SUBJECT (Common Name) ------------------------------------ THUMBPRINT ------------------------------- program name --------------- installer url

#region Handle validation errors --------------------------------------------------------------------------------------------------

if ($script:varFail -ge 1) {
    write-host "! ERROR: Unable to validate digital certificate for ScreenConnect installer."
    write-host "  If the EXE is signed with a custom digital certificate, this Component will need to be edited and the correct"
    write-host "  signature information placed into the script body; for more information on this process, copy the Component and"
    write-host "  scrutinise the comments left in the code. This should detail the process from start to finish."
    write-host "- Cannot validate installer; exiting."
    exit 1
}

#region Closeout ------------------------------------------------------------------------------------------------------------------

write-host "- Installing ScreenConnect..."
Start-Process -Wait -FilePath "ScreenConnect.ClientSetup.exe" -ArgumentList "/qn" -PassThru
createJoinLink