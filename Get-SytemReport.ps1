<#
.SYNOPSIS
    Uproszczony generator raportu systemowego w formacie HTML.

.DESCRIPTION
    Ten skrypt generuje szczegółowy raport zawierający informacje o sprzęcie,
    systemie operacyjnym, użytkownikach, pamięci RAM, BIOS, dyskach i sieci.

.PARAMETER OutputPath
    Ścieżka do pliku wyjściowego HTML. Domyślnie: .\SystemReport.html

.EXAMPLE
    .\SystemReport_Simplified.ps1
    Generuje raport z domyślnymi parametrami

.EXAMPLE
    .\SystemReport_Simplified.ps1 -OutputPath "C:\Reports\report.html"
    Generuje raport w określonej lokalizacji

.NOTES
    Author: System Administrator
    Requires: PowerShell 5.1+, PSWriteHTML module
    Version: 2.0 Simplified
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = ".\SystemReport.html"
)

#Requires -Version 5.1

# ============================================================================
# KONFIGURACJA
# ============================================================================

$Config = @{
    HeaderColor = '#00364b'
}

# ============================================================================
# FUNKCJE POMOCNICZE
# ============================================================================

function Initialize-PSWriteHTML {
    <#
    .SYNOPSIS
        Sprawdza i importuje moduł PSWriteHTML.
    .DESCRIPTION
        Funkcja weryfikuje dostępność modułu PSWriteHTML.
        Jeśli moduł nie jest zainstalowany, automatycznie go instaluje.
    #>
    if (-not (Get-Module -ListAvailable -Name PSWriteHTML)) {
        Write-Warning "Moduł PSWriteHTML nie jest zainstalowany."
        Write-Host "Instalowanie modułu PSWriteHTML..." -ForegroundColor Yellow
        
        try {
            Install-Module -Name PSWriteHTML -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host "Moduł PSWriteHTML został pomyślnie zainstalowany." -ForegroundColor Green
        }
        catch {
            Write-Error "Nie udało się zainstalować modułu PSWriteHTML: $_"
            exit 1
        }
    }
    
    Import-Module PSWriteHTML -ErrorAction Stop
}

function Get-ComputerData {
    <#
    .SYNOPSIS
        Zbiera podstawowe informacje o komputerze.
    .DESCRIPTION
        Funkcja wykorzystuje WMI/CIM do zebrania informacji o nazwie komputera,
        producencie, modelu, systemie operacyjnym i konfiguracji.
    .OUTPUTS
        Hashtable z danymi komputera
    #>
    try {
        $ComputerInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        
        [ordered]@{
            'Typ urządzenia' = $ComputerInfo.ChassisSKUNumber
            'Nazwa komputera' = $ComputerInfo.Name
            'Producent' = $ComputerInfo.Manufacturer
            'Model' = $ComputerInfo.Model
            'Domena/Grupa robocza' = if ($ComputerInfo.PartOfDomain) { $ComputerInfo.Domain } else { $ComputerInfo.Workgroup }
            'System operacyjny' = $OSInfo.Caption
            'Wersja OS' = $OSInfo.Version
            'Architektura' = $OSInfo.OSArchitecture
            'Data instalacji' = $OSInfo.InstallDate
            'Ostatni rozruch' = $OSInfo.LastBootUpTime
            'Bieżący użytkownik' = $ComputerInfo.UserName
        }
    }
    catch {
        Write-Error "Błąd podczas pobierania informacji o komputerze: $_"
        return @{}
    }
}

function Get-ProcessorData {
    <#
    .SYNOPSIS
        Zbiera informacje o procesorze.
    .DESCRIPTION
        Funkcja pobiera szczegółowe dane procesora: nazwę, liczbę rdzeni,
        liczbę procesorów logicznych oraz maksymalną częstotliwość taktowania.
    .OUTPUTS
        Hashtable z danymi procesora
    #>
    try {
        $ProcessorInfo = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        
        [ordered]@{
            'Procesor' = $ProcessorInfo.Name
            'Rdzenie' = $ProcessorInfo.NumberOfCores
            'Procesory logiczne' = $ProcessorInfo.NumberOfLogicalProcessors
            'Maksymalna częstotliwość' = "$($ProcessorInfo.MaxClockSpeed) MHz"
        }
    }
    catch {
        Write-Error "Błąd podczas pobierania informacji o procesorze: $_"
        return @{}
    }
}

function Get-MemoryData {
    <#
    .SYNOPSIS
        Zbiera informacje o pamięci RAM.
    .DESCRIPTION
        Funkcja oblicza całkowitą, wolną i używaną pamięć RAM,
        a także procent wykorzystania pamięci.
    .OUTPUTS
        PSCustomObject z danymi pamięci
    #>
    try {
        $ComputerInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $OSInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        
        $TotalRAM = [math]::Round($ComputerInfo.TotalPhysicalMemory / 1GB, 2)
        $FreeRAM = [math]::Round($OSInfo.FreePhysicalMemory / 1MB, 2)
        $UsedRAM = [math]::Round($TotalRAM - $FreeRAM, 2)
        
        [PSCustomObject]@{
            'Całkowita RAM (GB)' = $TotalRAM
            'Wolna RAM (GB)' = $FreeRAM
            'Używana RAM (GB)' = $UsedRAM
            'Wykorzystanie (%)' = [math]::Round(($UsedRAM / $TotalRAM) * 100, 2)
        }
    }
    catch {
        Write-Error "Błąd podczas pobierania informacji o pamięci: $_"
        return $null
    }
}

function Get-BIOSData {
    <#
    .SYNOPSIS
        Zbiera informacje o BIOS.
    .DESCRIPTION
        Funkcja pobiera dane BIOS/UEFI, w tym producenta,
        wersję, datę wydania i numer seryjny.
    .OUTPUTS
        Hashtable z danymi BIOS
    #>
    try {
        $BIOSInfo = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        
        [ordered]@{
            'Producent' = $BIOSInfo.Manufacturer
            'Wersja' = $BIOSInfo.SMBIOSBIOSVersion
            'Data wydania' = $BIOSInfo.ReleaseDate
            'Numer seryjny' = $BIOSInfo.SerialNumber
        }
    }
    catch {
        Write-Error "Błąd podczas pobierania informacji o BIOS: $_"
        return @{}
    }
}

function Get-DiskData {
    <#
    .SYNOPSIS
        Zbiera informacje o dyskach.
    .DESCRIPTION
        Funkcja pobiera dane wszystkich lokalnych dysków: literę dysku,
        system plików, pojemność, wolne miejsce i procent wykorzystania.
    .OUTPUTS
        Array obiektów PSCustomObject z danymi dysków
    #>
    try {
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop |
            ForEach-Object {
                [PSCustomObject]@{
                    'Dysk' = $_.DeviceID
                    'System plików' = $_.FileSystem
                    'Pojemność (GB)' = [math]::Round($_.Size / 1GB, 2)
                    'Wolne miejsce (GB)' = [math]::Round($_.FreeSpace / 1GB, 2)
                    'Wykorzystane (%)' = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 2)
                }
            }
    }
    catch {
        Write-Error "Błąd podczas pobierania informacji o dyskach: $_"
        return @()
    }
}

function Get-NetworkData {
    <#
    .SYNOPSIS
        Zbiera informacje o kartach sieciowych.
    .DESCRIPTION
        Funkcja pobiera konfigurację wszystkich aktywnych kart sieciowych:
        adres IP, maskę podsieci, bramę domyślną, serwery DNS i status DHCP.
    .OUTPUTS
        Array obiektów PSCustomObject z danymi sieci
    #>
    try {
        Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction Stop |
            ForEach-Object {
                [PSCustomObject]@{
                    'Adapter' = $_.Description
                    'Adres IP' = ($_.IPAddress -join ', ')
                    'Maska podsieci' = ($_.IPSubnet -join ', ')
                    'Brama domyślna' = if ($_.DefaultIPGateway) { ($_.DefaultIPGateway -join ', ') } else { "Brak" }
                    'Serwery DNS' = ($_.DNSServerSearchOrder -join ', ')
                    'DHCP włączone' = $_.DHCPEnabled
                }
            }
    }
    catch {
        Write-Error "Błąd podczas pobierania informacji o sieci: $_"
        return @()
    }
}

function Get-LocalUsersData {
    <#
    .SYNOPSIS
        Zbiera informacje o lokalnych użytkownikach.
    .DESCRIPTION
        Funkcja pobiera listę wszystkich lokalnych kont użytkowników
        wraz z ich statusem, datą ostatniego logowania i wymaganiami dotyczącymi hasła.
    .OUTPUTS
        Array obiektów PSCustomObject z danymi użytkowników
    #>
    try {
        Get-LocalUser -ErrorAction Stop |
            ForEach-Object {
                [PSCustomObject]@{
                    'Nazwa użytkownika' = $_.Name
                    'Włączone' = $_.Enabled
                    'Ostatnie logowanie' = if ($_.LastLogon) { $_.LastLogon } else { "Nigdy" }
                    'Wymagane hasło' = $_.PasswordRequired
                }
            }
    }
    catch {
        Write-Error "Błąd podczas pobierania informacji o użytkownikach: $_"
        return @()
    }
}

# ============================================================================
# GŁÓWNA LOGIKA
# ============================================================================

try {
    Write-Host "Inicjalizacja modułu PSWriteHTML..." -ForegroundColor Cyan
    Initialize-PSWriteHTML
    
    Write-Host "Zbieranie informacji systemowych..." -ForegroundColor Cyan
    
    # Zbieranie danych
    $ComputerData = Get-ComputerData
    $ProcessorData = Get-ProcessorData
    $RamData = Get-MemoryData
    $BIOSData = Get-BIOSData
    $DiskData = Get-DiskData
    $NetworkData = Get-NetworkData
    $LocalUsersData = Get-LocalUsersData
    
    Write-Host "Generowanie raportu HTML..." -ForegroundColor Cyan
    
    # Generowanie raportu
    New-HTML -TitleText "Raport systemowy - $env:COMPUTERNAME" -Online -FilePath $OutputPath {
        
        # Sekcja: Informacje o komputerze
        New-HTMLSection -HeaderText "Informacje o komputerze - $env:COMPUTERNAME" -HeaderBackGroundColor $Config.HeaderColor {
            New-HTMLPanel -Invisible {
                New-HTMLSection -HeaderText "Urządzenie" -HeaderBackGroundColor $Config.HeaderColor {
                    New-HTMLTable -DataTable $ComputerData -HideFooter -HideButtons -DisableInfo -DisablePaging -DisableSearch -DisableOrdering
                 }
            }
            New-HTMLPanel -Invisible {
                New-HTMLSection -HeaderText "Procesor" -HeaderBackGroundColor $Config.HeaderColor {
                    New-HTMLTable -DataTable $ProcessorData -HideFooter -HideButtons -DisableInfo -DisablePaging -DisableSearch -DisableOrdering
                }
                
                New-HTMLSection -HeaderText "BIOS" -HeaderBackGroundColor $Config.HeaderColor {
                    New-HTMLTable -DataTable $BIOSData -HideFooter -HideButtons -DisableInfo -DisablePaging -DisableSearch -DisableOrdering
                }
            }
            
            New-HTMLPanel -Invisible {
                New-HTMLSection -HeaderText "Ustawienia sieciowe" -HeaderBackGroundColor $Config.HeaderColor {
                    New-HTMLTable -DataTable $NetworkData -HideFooter -HideButtons -DisableInfo -DisablePaging -DisableSearch -DisableOrdering
                }
                
                New-HTMLSection -HeaderText "Dyski" -HeaderBackGroundColor $Config.HeaderColor {
                    New-HTMLTable -DataTable $DiskData -HideFooter -HideButtons -DisableInfo -DisablePaging -DisableSearch -DisableOrdering {
                        New-TableCondition -Name 'Wykorzystane (%)' -ComparisonType number -Operator gt -Value 90 -BackgroundColor Red -Color White
                        New-TableCondition -Name 'Wykorzystane (%)' -ComparisonType number -Operator gt -Value 75 -BackgroundColor Orange -Color White
                        New-TableCondition -Name 'Wykorzystane (%)' -ComparisonType number -Operator le -Value 75 -BackgroundColor LightGreen
                    }
                }
                
                New-HTMLSection -HeaderText "Pamięć (RAM)" -HeaderBackGroundColor $Config.HeaderColor {
                    New-HTMLTable -DataTable $RamData -HideFooter -HideButtons -DisableInfo -DisablePaging -DisableSearch -DisableOrdering {
                        New-HTMLTableCondition -Name 'Wykorzystanie (%)' -ComparisonType number -Operator gt -Value 90 -BackgroundColor Red -Color White
                        New-HTMLTableCondition -Name 'Wykorzystanie (%)' -ComparisonType number -Operator gt -Value 75 -BackgroundColor Orange -Color White
                    }
                }
            }
            
            New-HTMLPanel -Invisible {
                New-HTMLSection -HeaderText "Lokalni użytkownicy" -HeaderBackGroundColor $Config.HeaderColor {
                    New-HTMLTable -DataTable $LocalUsersData -HideFooter -HideButtons -DisableInfo -DisablePaging -DisableSearch -DisableOrdering
                }
            }
        }
        
        # Stopka
        New-HTMLFooter {
            New-HTMLText -Text "Raport wygenerowany: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Komputer: $env:COMPUTERNAME | Użytkownik: $env:USERNAME" -Alignment center
        }
        
    } -ShowHTML
    
    Write-Host "`nRaport został pomyślnie wygenerowany: $OutputPath" -ForegroundColor Green
    
}
catch {
    Write-Error "Wystąpił błąd podczas generowania raportu: $_"
    exit 1
}
