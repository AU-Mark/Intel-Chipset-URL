# Intel Chipset Download URL

[![Update Intel Chipset Data](https://github.com/AU-Mark/Intel-Chipset-URL/actions/workflows/update-intel-chipset-data.yml/badge.svg)](https://github.com/AU-Mark/Intel-Chipset-URL/actions/workflows/update-intel-chipset-data.yml)

Automated daily mirror of the Intel Chipset Device Software (Chipset INF Utility) installer from Intel's official [download center](https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html).

Intel serves `SetupChipset.exe` from `downloadmirror.intel.com` behind Akamai bot protection that returns an empty HTTP 202 to scripted clients (`Invoke-WebRequest`, `curl`, BITS). Endpoints therefore cannot download the installer directly. This repository solves that: a GitHub Actions pipeline drives a real headless Chrome (the one client Akamai lets through), downloads each new release, and republishes it as a GitHub Release asset that downloads normally from any client. The current version, checksum, and download URL are published in a small JSON catalog.

## Features

- **Daily Updates**: Checks for a new Intel Chipset release every day at 8:00 AM UTC
- **Bot-Wall Bypass**: Drives headless Chrome via Selenium to both scrape the page and download the installer, because Intel's Akamai protection blocks scripted HTTP clients
- **Rehosted Installer**: Publishes `SetupChipset.exe` as a GitHub Release asset so any endpoint can download it with a plain HTTPS GET
- **Integrity**: Captures and publishes the SHA256 so consumers can verify the download
- **Version Tracking**: Keeps a history of previous versions under `Versions`

## JSON Schema

```json
{
  "Product": "Intel Chipset Device Software",
  "LastUpdated": "2026-06-25T18:30:00Z",
  "SourceUrl": "https://www.intel.com/content/www/us/en/download/19347/chipset-inf-utility.html",
  "Latest": {
    "Version": "10.1.20398.8776",
    "ReleaseDate": "01/08/2026",
    "DownloadId": "872506",
    "IntelUrl": "https://downloadmirror.intel.com/872506/SetupChipset.exe",
    "ReadmeUrl": "https://downloadmirror.intel.com/872506/Readme.txt",
    "Url": "https://github.com/AU-Mark/Intel-Chipset-URL/releases/download/v10.1.20398.8776/SetupChipset.exe",
    "SHA256": "5DA882149294917142CEA8666832E37F4D846FF04E14A313913B6A22F05E0CE2",
    "FileSize": 111103856,
    "UpdatedOn": "2026-06-25T18:30:00Z"
  },
  "Versions": {}
}
```

## Usage

### Raw JSON URL

```text
https://raw.githubusercontent.com/AU-Mark/Intel-Chipset-URL/main/data/IntelChipset.json
```

### Stable installer URL

The newest installer is always available at this permanent URL (no JSON parsing required):

```text
https://github.com/AU-Mark/Intel-Chipset-URL/releases/latest/download/SetupChipset.exe
```

### PowerShell Example

```powershell
# Get the current installer URL and checksum from the catalog
$intel = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/AU-Mark/Intel-Chipset-URL/main/data/IntelChipset.json"
Write-Host "Intel Chipset $($intel.Latest.Version) - $($intel.Latest.Url)"

# Download the installer from GitHub (no Akamai bot-wall here)
Invoke-WebRequest -Uri $intel.Latest.Url -OutFile "SetupChipset.exe"

# Verify integrity
$hash = (Get-FileHash -Path "SetupChipset.exe" -Algorithm SHA256).Hash
if ($hash -ne $intel.Latest.SHA256) { throw "SHA256 mismatch" }
```

## JSON Fields

| Field | Description |
| ----- | ----------- |
| `Version` | Full four-part version, for example `10.1.20398.8776` |
| `ReleaseDate` | Intel's published release date for the package |
| `DownloadId` | The numeric `downloadmirror.intel.com` mirror ID |
| `IntelUrl` | The original Intel mirror URL (source of record; not directly downloadable by scripts) |
| `ReadmeUrl` | Direct URL for the matching `Readme.txt` |
| `Url` | The GitHub Release asset URL consumers download (`SetupChipset.exe`) |
| `SHA256` | SHA256 checksum of the published installer |
| `FileSize` | Installer size in bytes |

## How It Works

1. **Scrape**: Headless Chrome loads the Intel download page; a regex extracts the `downloadmirror.intel.com/{id}/SetupChipset.exe` ID and rebuilds the canonical URL. If the page DOM hides the version or date, the same browser reads the plain-text `Readme.txt` beside the installer for an authoritative `Version:` and `Date:`.
2. **Version Comparison**: Work only happens when a new version is detected.
3. **Download**: On a version change, headless Chrome downloads the ~106 MB `SetupChipset.exe` (Akamai blocks scripted download clients, so a real browser is required).
4. **Publish**: The workflow creates a GitHub Release tagged `v{version}` and uploads the installer as an asset.
5. **Catalog**: `data/IntelChipset.json` is updated with the GitHub Release URL, SHA256, and size, then committed. Previous versions are archived under `Versions`.

## Manual Trigger

The workflow can be triggered manually from the Actions tab when an immediate refresh is needed.

## License

This tool mirrors a publicly available installer from intel.com for internal deployment convenience. Intel software is subject to the applicable Intel software license agreement presented on the download page.
