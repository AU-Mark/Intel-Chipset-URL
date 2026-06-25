<#
.SYNOPSIS
    Updates the direct Intel Chipset Device Software (Chipset INF Utility) download link
    from Intel's official download center.

.DESCRIPTION
    Fetches the latest Intel Chipset Device Software download information from Intel's
    official download page (download/19347) and saves it as a standardized JSON file
    with version tracking.

    Uses Selenium with stealth options to drive a real headless Chrome. This is required
    because Intel's download center is fronted by Akamai bot protection that returns an
    empty HTTP 202 to scripted HTTP clients (Invoke-WebRequest / curl). A genuine browser
    gets through.

    Extraction strategy (robust, multi-source):
      1. Load the download page and regex the page source for the SetupChipset.exe
         download ID:  downloadmirror.intel.com/<ID>/SetupChipset.exe
      2. Try to read Version, Date and SHA256 from the page itself.
      3. If Version or Date are missing from the page DOM, navigate the same browser to
         the Readme.txt that sits beside the installer
         (downloadmirror.intel.com/<ID>/Readme.txt). That file is plain text with stable
         "Version:" and "Date:" header lines and is the authoritative version source.

    The JSON maintains:
      - "Latest" entry with the current version info and the direct download URL
      - Historical versions preserved under "Versions" with their original URLs

.PARAMETER OutputPath
    Path to the data folder. Defaults to ../data relative to script location.

.PARAMETER SkipVersionCheck
    Skip checking if the version has changed (always rewrite the JSON).

.EXAMPLE
    .\Update-IntelChipsetData.ps1

.EXAMPLE
    .\Update-IntelChipsetData.ps1 -OutputPath "C:\Data" -Verbose
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$SkipVersionCheck
)

# Set output path
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot "..\data"
}

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$Url = 'https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html'
$JsonPath = Join-Path $OutputPath "IntelChipset.json"
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Intel Chipset Download Data Updater" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Timestamp: $timestamp" -ForegroundColor Gray
Write-Host "Output: $JsonPath" -ForegroundColor Gray
Write-Host ""

#region Helper Functions

function Get-IntelChipsetDataSelenium {
    <#
    .SYNOPSIS
        Fetches Intel Chipset Device Software download data using Selenium.
    #>
    param([string]$Url)

    Write-Host "[Intel] Fetching data using Selenium..." -ForegroundColor Cyan
    Write-Host "[Intel] URL: $Url" -ForegroundColor Gray

    # Try to find the Selenium module
    $seleniumModule = Get-Module -ListAvailable -Name Selenium
    if (-not $seleniumModule) {
        Write-Error "[Intel] Selenium module not found. Install with: Install-Module -Name Selenium"
        return $null
    }

    # Find Selenium assemblies
    $seleniumPath = $seleniumModule.ModuleBase
    $assembliesPath = Join-Path $seleniumPath "assemblies"
    $webDriverDll = Join-Path $assembliesPath "WebDriver.dll"

    if (-not (Test-Path $webDriverDll)) {
        Write-Error "[Intel] WebDriver.dll not found at: $webDriverDll"
        return $null
    }

    # Load WebDriver
    if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq "WebDriver" })) {
        Add-Type -Path $webDriverDll -ErrorAction Stop
    }

    $driver = $null

    try {
        # Create Chrome options with stealth settings (mirrors the Java 8 scraper)
        $chromeOptions = New-Object OpenQA.Selenium.Chrome.ChromeOptions
        $chromeOptions.AddExcludedArgument("enable-automation")
        $chromeOptions.AddArgument("--disable-blink-features=AutomationControlled")
        $chromeOptions.AddArgument("--disable-extensions")
        $chromeOptions.AddArgument("--disable-http2")
        $chromeOptions.AddArgument("--no-sandbox")
        $chromeOptions.AddArgument("--disable-dev-shm-usage")
        $chromeOptions.AddArgument("--disable-gpu")
        $chromeOptions.AddArgument("--disable-infobars")
        $chromeOptions.AddArgument("--disable-notifications")
        $chromeOptions.AddArgument("--disable-popup-blocking")
        $chromeOptions.AddArgument("--window-size=1920,1080")
        $chromeOptions.AddArgument("--start-maximized")
        $chromeOptions.AddArgument("--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36")
        $chromeOptions.AddArgument("--lang=en-US")
        $chromeOptions.AddArgument("--headless=new")
        $chromeOptions.AddArgument("--log-level=3")
        $chromeOptions.AddArgument("--silent")

        # Create the Chrome service
        $chromeDriverPath = Join-Path $assembliesPath "chromedriver.exe"
        if (Test-Path $chromeDriverPath) {
            $chromeService = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService($assembliesPath)
        } else {
            $chromeService = [OpenQA.Selenium.Chrome.ChromeDriverService]::CreateDefaultService()
        }
        $chromeService.HideCommandPromptWindow = $true
        $chromeService.SuppressInitialDiagnosticInformation = $true

        Write-Host "[Intel] Starting Chrome..." -ForegroundColor Cyan
        $driver = New-Object OpenQA.Selenium.Chrome.ChromeDriver($chromeService, $chromeOptions)
        $driver.Manage().Timeouts().PageLoad = [TimeSpan]::FromSeconds(60)

        Write-Host "[Intel] Navigating to download page..." -ForegroundColor Cyan
        $driver.Navigate().GoToUrl($Url)

        # Wait for the React download page to render
        Start-Sleep -Seconds 6

        Write-Host "[Intel] Page loaded: $($driver.Title)" -ForegroundColor Green

        $html = $driver.PageSource

        # Save the page source for debugging (gitignored). Helps tune selectors after a run.
        try {
            $debugPath = Join-Path $PSScriptRoot "..\intel_page.html"
            $html | Out-File -FilePath $debugPath -Encoding UTF8
        } catch { }

        # Hard block / error detection
        if ($html -match "Access Denied|Request unsuccessful|Reference&#32;&#35;|ERR_|can't be reached") {
            throw "Page load failed or blocked by bot protection"
        }

        # ----------------------------------------------------------------
        # 1) Extract the SetupChipset.exe download ID (required)
        #    Capture only the numeric ID and rebuild the canonical URL so we
        #    are tolerant of escaped slashes (\/), query strings, etc.
        # ----------------------------------------------------------------
        $downloadId = $null
        $idPattern = 'downloadmirror\.intel\.com\\?/(\d+)\\?/SetupChipset\.exe'
        $idMatches = [regex]::Matches($html, $idPattern, 'IgnoreCase')
        if ($idMatches.Count -gt 0) {
            # If multiple, prefer the highest ID (newest mirror) for safety
            $ids = @()
            foreach ($m in $idMatches) { $ids += [int]$m.Groups[1].Value }
            $downloadId = ($ids | Sort-Object -Descending | Select-Object -First 1).ToString()
            Write-Host "[Intel] Found download ID: $downloadId" -ForegroundColor Green
        } else {
            Write-Error "[Intel] Could not find a downloadmirror SetupChipset.exe ID in the page source"
            return $null
        }

        $downloadUrl = "https://downloadmirror.intel.com/$downloadId/SetupChipset.exe"
        $readmeUrl   = "https://downloadmirror.intel.com/$downloadId/Readme.txt"

        # ----------------------------------------------------------------
        # 2) Try to read Version / Date / SHA256 from the page DOM
        # ----------------------------------------------------------------
        $version = $null
        $releaseDate = $null
        $sha256 = $null

        # Version: chipset major is currently 10 (e.g. 10.1.20524.8822)
        $vm = [regex]::Match($html, '\b(10\.\d+\.\d+\.\d+)\b')
        if ($vm.Success) { $version = $vm.Groups[1].Value }

        # SHA256: Intel publishes checksums in the download detail section
        $sm = [regex]::Match($html, '(?i)SHA[- ]?256[^0-9A-Fa-f]{0,20}([A-Fa-f0-9]{64})')
        if ($sm.Success) { $sha256 = $sm.Groups[1].Value.ToUpper() }

        # Release date: Intel shows a date field on the page (best effort here)
        $dm = [regex]::Match($html, '(?i)(?:Date|Released?)[^0-9]{0,20}(\d{1,2}/\d{1,2}/\d{4})')
        if ($dm.Success) { $releaseDate = $dm.Groups[1].Value }

        # ----------------------------------------------------------------
        # 3) Fallback: read the Readme.txt for authoritative Version / Date
        #    The Readme is plain text with stable header lines.
        # ----------------------------------------------------------------
        if (-not $version -or -not $releaseDate) {
            Write-Host "[Intel] Reading Readme.txt for authoritative version/date: $readmeUrl" -ForegroundColor Cyan
            try {
                $driver.Navigate().GoToUrl($readmeUrl)
                Start-Sleep -Seconds 3
                $readmeText = $driver.PageSource

                if (-not $version) {
                    $rv = [regex]::Match($readmeText, '(?i)Version[:\s]+([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)')
                    if ($rv.Success) {
                        $version = $rv.Groups[1].Value
                        Write-Host "[Intel] Version from Readme: $version" -ForegroundColor Green
                    }
                }

                if (-not $releaseDate) {
                    $rd = [regex]::Match($readmeText, '(?i)Date[:\s]+([0-9]{1,2}/[0-9]{1,2}/[0-9]{4})')
                    if ($rd.Success) {
                        $releaseDate = $rd.Groups[1].Value
                        Write-Host "[Intel] Date from Readme: $releaseDate" -ForegroundColor Green
                    }
                }
            } catch {
                Write-Warning "[Intel] Could not read Readme.txt: $_"
            }
        }

        if (-not $version) {
            Write-Error "[Intel] Could not extract a version number from the page or Readme"
            return $null
        }

        # Report what we captured
        Write-Host "[Intel] Version : $version" -ForegroundColor Green
        Write-Host "[Intel] URL     : $downloadUrl" -ForegroundColor Green
        Write-Host "[Intel] Date    : $(if ($releaseDate) { $releaseDate } else { 'not found' })" -ForegroundColor Gray
        Write-Host "[Intel] SHA256  : $(if ($sha256) { $sha256 } else { 'not found on page' })" -ForegroundColor Gray

        # Build the result object
        $result = [PSCustomObject]@{
            Version     = $version
            ReleaseDate = $releaseDate
            DownloadId  = $downloadId
            Url         = $downloadUrl
            ReadmeUrl   = $readmeUrl
            SHA256      = $sha256
        }

        return $result

    } catch {
        Write-Error "[Intel] Selenium failed: $_"
        return $null
    } finally {
        if ($driver) {
            try {
                Write-Host "[Intel] Closing browser..." -ForegroundColor Gray
                $driver.Quit()
            } catch { }
        }
    }
}

#endregion

#region Main Execution

# Fetch current data
$intelData = Get-IntelChipsetDataSelenium -Url $Url

if (-not $intelData) {
    Write-Error "[Intel] Failed to fetch Intel Chipset data"
    exit 1
}

# Load existing JSON if present
$existingData = $null
if (Test-Path $JsonPath) {
    try {
        $existingData = Get-Content $JsonPath -Raw | ConvertFrom-Json
        Write-Host "[Intel] Loaded existing data from: $JsonPath" -ForegroundColor Cyan
    } catch {
        Write-Warning "[Intel] Could not parse existing JSON, will create new file"
    }
}

# Check if the version has changed
$versionChanged = $true
if ($existingData -and $existingData.Latest -and -not $SkipVersionCheck) {
    if ($existingData.Latest.Version -eq $intelData.Version) {
        Write-Host "[Intel] Version unchanged ($($intelData.Version)). Skipping update." -ForegroundColor Yellow
        $versionChanged = $false
    }
}

if ($versionChanged) {
    Write-Host "[Intel] Processing version update..." -ForegroundColor Cyan

    # Initialize or update the JSON structure
    $jsonOutput = if ($existingData) {
        $existingData
    } else {
        [PSCustomObject]@{
            Product     = "Intel Chipset Device Software"
            LastUpdated = $timestamp
            SourceUrl   = $Url
            Latest      = $null
            Versions    = [PSCustomObject]@{}
        }
    }

    # Some older JSON files may not have a Versions container; ensure it exists
    if (-not ($jsonOutput.PSObject.Properties.Name -contains 'Versions') -or $null -eq $jsonOutput.Versions) {
        $jsonOutput | Add-Member -NotePropertyName 'Versions' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    # If there was a previous "Latest", archive it under Versions.
    # Skip the "0.0.0.0" seed placeholder so it never pollutes the version history.
    if ($existingData -and $existingData.Latest -and $existingData.Latest.Version -ne $intelData.Version -and $existingData.Latest.Version -ne '0.0.0.0') {
        $oldVersion = $existingData.Latest.Version
        Write-Host "[Intel] Archiving previous version: $oldVersion" -ForegroundColor Cyan

        $jsonOutput.Versions | Add-Member -NotePropertyName $oldVersion -NotePropertyValue ([PSCustomObject]@{
            Version     = $existingData.Latest.Version
            ReleaseDate = $existingData.Latest.ReleaseDate
            DownloadId  = $existingData.Latest.DownloadId
            Url         = $existingData.Latest.Url
            ReadmeUrl   = $existingData.Latest.ReadmeUrl
            SHA256      = $existingData.Latest.SHA256
            ArchivedOn  = $timestamp
        }) -Force
    }

    # Update Latest
    $jsonOutput.Latest = [PSCustomObject]@{
        Version     = $intelData.Version
        ReleaseDate = $intelData.ReleaseDate
        DownloadId  = $intelData.DownloadId
        Url         = $intelData.Url
        ReadmeUrl   = $intelData.ReadmeUrl
        SHA256      = $intelData.SHA256
        UpdatedOn   = $timestamp
    }

    $jsonOutput.LastUpdated = $timestamp

    # Save JSON
    $jsonOutput | ConvertTo-Json -Depth 10 | Out-File -FilePath $JsonPath -Encoding UTF8
    Write-Host "[Intel] Saved to: $JsonPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Version: $($intelData.Version)" -ForegroundColor White
Write-Host "  Release Date: $(if ($intelData.ReleaseDate) { $intelData.ReleaseDate } else { 'unknown' })" -ForegroundColor White
Write-Host "  Download ID: $($intelData.DownloadId)" -ForegroundColor White
Write-Host "  URL: $($intelData.Url)" -ForegroundColor White
Write-Host "  SHA256: $(if ($intelData.SHA256) { $intelData.SHA256 } else { 'not captured' })" -ForegroundColor White
Write-Host "  Version Changed: $versionChanged" -ForegroundColor $(if ($versionChanged) { 'Green' } else { 'Yellow' })
Write-Host "========================================" -ForegroundColor Cyan

exit 0

#endregion
