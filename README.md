# Intel Chipset Download URL

[![Update Intel Chipset Data](https://github.com/AU-Mark/Intel-Chipset-URL/actions/workflows/update-intel-chipset-data.yml/badge.svg)](https://github.com/AU-Mark/Intel-Chipset-URL/actions/workflows/update-intel-chipset-data.yml)

Automated daily scraper for the direct Intel Chipset Device Software (Chipset INF Utility) download link from Intel's official [download center](https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html).

Intel hosts each release of `SetupChipset.exe` behind an opaque, per-release mirror ID (for example `downloadmirror.intel.com/860883/SetupChipset.exe`). Every new release gets a brand new ID, so any hardcoded link eventually breaks. This repository tracks the current ID so downstream automation always has a working direct link.

## Features

- **Daily Updates**: Checks for a new Intel Chipset release every day at 8:00 AM UTC
- **Direct Download URL**: Publishes the exact `downloadmirror.intel.com/{id}/SetupChipset.exe` link
- **Version Tracking**: Keeps a history of previous versions and their mirror URLs
- **Integrity Data**: Captures the published SHA256 checksum when Intel exposes it
- **Bot-Wall Resistant**: Drives a real headless Chrome via Selenium, because Intel's Akamai protection returns an empty HTTP 202 to scripted HTTP clients

## JSON Schema

```json
{
  "Product": "Intel Chipset Device Software",
  "LastUpdated": "2026-06-25T08:05:00Z",
  "SourceUrl": "https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html",
  "Latest": {
    "Version": "10.1.20398.8776",
    "ReleaseDate": "01/08/2026",
    "DownloadId": "872506",
    "Url": "https://downloadmirror.intel.com/872506/SetupChipset.exe",
    "ReadmeUrl": "https://downloadmirror.intel.com/872506/Readme.txt",
    "SHA256": "5DA882149294917142CEA8666832E37F4D846FF04E14A313913B6A22F05E0CE2",
    "UpdatedOn": "2026-06-25T18:06:11Z"
  },
  "Versions": {
    "10.1.19913.8597": {
      "Version": "10.1.19913.8597",
      "ReleaseDate": "07/15/2025",
      "DownloadId": "843223",
      "Url": "https://downloadmirror.intel.com/843223/SetupChipset.exe",
      "ArchivedOn": "2026-06-25T18:06:11Z"
    }
  }
}
```

## Usage

### Raw JSON URL

```text
https://raw.githubusercontent.com/AU-Mark/Intel-Chipset-URL/main/data/IntelChipset.json
```

### PowerShell Example

```powershell
# Get the latest Intel Chipset direct download URL
$intel = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/AU-Mark/Intel-Chipset-URL/main/data/IntelChipset.json"
$downloadUrl = $intel.Latest.Url
Write-Host "Intel Chipset $($intel.Latest.Version) - $downloadUrl"

# Download the installer
Invoke-WebRequest -Uri $downloadUrl -OutFile "SetupChipset.exe"

# Optional: verify integrity if a checksum was captured
if ($intel.Latest.SHA256) {
    $hash = (Get-FileHash -Path "SetupChipset.exe" -Algorithm SHA256).Hash
    if ($hash -ne $intel.Latest.SHA256) { throw "SHA256 mismatch" }
}
```

## JSON Fields

| Field | Description |
| ----- | ----------- |
| `Version` | Full four-part version, for example `10.1.20398.8776` |
| `ReleaseDate` | Intel's published release date for the package |
| `DownloadId` | The numeric `downloadmirror.intel.com` mirror ID |
| `Url` | Direct download URL for `SetupChipset.exe` |
| `ReadmeUrl` | Direct URL for the matching `Readme.txt` |
| `SHA256` | Published SHA256 checksum, or `null` if not exposed on the page |

## How It Works

1. **Selenium Stealth**: Drives Chrome with stealth options to bypass Intel's bot detection
2. **ID Extraction**: Regexes the page source for `downloadmirror.intel.com/{id}/SetupChipset.exe` and rebuilds the canonical URL
3. **Readme Oracle**: If the page DOM does not expose the version or date, the same browser reads the plain-text `Readme.txt` beside the installer for an authoritative `Version:` and `Date:`
4. **Version Comparison**: Only rewrites the JSON when a new version is detected
5. **Version Archiving**: Previous versions are preserved under the `Versions` object

## Manual Trigger

The workflow can be triggered manually from the Actions tab when an immediate refresh is needed. The first run after creating the repository will replace the provisional seed values with authoritative data scraped from Intel.

## License

This tool collects publicly available information from intel.com. Intel software is subject to the applicable Intel software license agreement presented on the download page.
