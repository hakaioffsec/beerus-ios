# App Store Module — Design Spec

## Overview

New BEERUS module that replicates ipatool's full functionality with a native iOS UI. Allows users to search the App Store, purchase free apps, browse version history, and download IPA files — all from the device.

**Approach:** Native Swift port of ipatool's API logic. No external binaries or Go dependencies.

## Architecture

```
BEERUS App (mobile user)
├── UI Layer (ViewControllers)
│   ├── AppStoreLoginViewController
│   ├── AppStoreSearchViewController
│   ├── AppDetailViewController
│   ├── VersionListViewController
│   └── DownloadViewController
├── Service Layer
│   ├── AppStoreService          — all App Store API calls
│   ├── AppStoreCredentialManager — iOS Keychain storage
│   ├── PlistPayload             — XML plist request builder
│   └── IPAProcessor             — ZIP patching + sinf replication
└── Daemon (root operations)
    └── INSTALL_IPA command      — install IPA on device
```

### Layer Responsibilities

- **UI Layer**: ViewControllers following existing ViewCode protocol pattern. Navigation via UINavigationController push/pop.
- **Service Layer**: `AppStoreService` — single class with all API endpoints. Async/await. Uses URLSession directly. Handles retry logic (token expiry, missing license).
- **Credential Storage**: `AppStoreCredentialManager` — wraps iOS Keychain (SecItemAdd/SecItemCopyMatching) to store `AppStoreAccount` as JSON. Service name: `io.hakaisecurity.beerus.appstore`.
- **Daemon**: New `INSTALL_IPA` command in beerusd for root-privileged IPA installation.

## App Store API Endpoints (ported from ipatool)

### 1. Bag

- **Purpose**: Fetch dynamic auth endpoint URL
- **Endpoint**: `GET https://init.itunes.apple.com/bag.xml?guid={GUID}`
- **Response**: XML plist containing `authenticateAccount` URL
- **GUID**: Derived from device identifier (uppercase, no colons)

### 2. Login

- **Purpose**: Authenticate with Apple ID, get passwordToken + directoryServicesID
- **Endpoint**: POST to URL from Bag response
- **Payload**: XML plist with `appleId`, `password` (appended with 2FA code if present), `guid`, `attempt`, `rmp=0`, `why=signIn`
- **Response headers**: `X-Set-Apple-Store-Front` (storefront), `pod` (server routing)
- **Flow**:
  1. First attempt with credentials
  2. If `failureType == "-5000"` (invalid credentials), retry (attempt 2)
  3. If 302 redirect, follow location
  4. If `customerMessage == "MZFinance.BadLogin.Configurator_message"` and no authCode → prompt 2FA
  5. Success: store Account in Keychain
- **Max attempts**: 4

### 3. Search

- **Purpose**: Search App Store by term
- **Endpoint**: `GET https://itunes.apple.com/search?entity=software,iPadSoftware&limit={limit}&media=software&term={term}&country={countryCode}`
- **Response**: JSON with `resultCount` and `results` array
- **Country code**: Extracted from storefront header (first 6 digits → country mapping)

### 4. Lookup

- **Purpose**: Resolve bundle ID to app details
- **Endpoint**: `GET https://itunes.apple.com/lookup?bundleId={bundleID}&country={countryCode}`
- **Response**: Same format as search

### 5. Purchase

- **Purpose**: Acquire license for free app
- **Endpoint**: `POST https://p{pod}-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/buyProduct`
- **Payload**: XML plist with `salableAdamId`, `guid`, pricing parameters
- **Pricing**: Try `STDQ` (App Store) first, fallback to `GAME` (Apple Arcade) if temporarily unavailable
- **Paid apps**: Rejected client-side (price > 0)

### 6. Download

- **Purpose**: Get download URL and sinf data for IPA
- **Endpoint**: `POST https://p{pod}-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid={GUID}`
- **Payload**: XML plist with `salableAdamId`, `guid`, `creditDisplay`, optional `externalVersionId`
- **Response**: `songList` array with `URL`, `sinfs`, `metadata`
- **Post-download processing**:
  1. Download IPA to temp file
  2. Open as ZIP, replicate all entries to new ZIP
  3. Add `iTunesMetadata.plist` (inject apple-id + userName from account)
  4. Replicate sinf files into `Payload/*.app/SC_Info/` (from Manifest.plist paths or Info.plist executable name)
  5. Remove temp file, keep final IPA
- **Retry**: On `failureType` 2034/2042/1008/5002 → re-login via bag. On 9610 → purchase first.

### 7. List Versions

- **Purpose**: Get all available external version identifiers
- **Endpoint**: Same as Download endpoint (without externalVersionId)
- **Response**: `metadata.softwareVersionExternalIdentifiers` array + `softwareVersionExternalIdentifier` (latest)

### 8. Get Version Metadata

- **Purpose**: Resolve version ID to display version string + release date
- **Endpoint**: Same as Download endpoint (with specific externalVersionId)
- **Method**: Partial ZIP read via HTTP Range requests — reads only `Payload/*.app/Info.plist` from remote IPA without full download
- **Extracts**: `CFBundleShortVersionString` and `releaseDate` from Info.plist

## Models

```swift
struct AppStoreAccount: Codable {
    let name: String
    let email: String
    let passwordToken: String
    let directoryServicesID: String
    let storeFront: String
    let password: String
    let pod: String
}

struct AppStoreApp: Codable {
    let id: Int64
    let bundleID: String
    let name: String
    let version: String
    let price: Double
}

struct DownloadResult {
    let destinationPath: String
    let sinfs: [SinfData]
}

struct SinfData {
    let id: Int64
    let data: Data
}

struct VersionMetadata {
    let displayVersion: String
    let releaseDate: Date
}

struct VersionListResult {
    let identifiers: [String]
    let latestID: String
}
```

## UI Screens

### 1. Login (`AppStoreLoginViewController`)

- Apple ID email field
- Password field (secure entry)
- 2FA code field (shown only when server requests it)
- "Sign In" button
- Status label for errors
- Auto-navigates to Search on success
- Skipped entirely if valid credentials exist in Keychain

### 2. Search (`AppStoreSearchViewController`)

- Search bar at top
- Account status indicator (email + checkmark)
- Logout button (revoke credentials)
- UITableView with search results
- Each cell: app icon placeholder + app name + bundle ID
- Tap cell → push AppDetailViewController
- Empty state with instructions

### 3. App Detail (`AppDetailViewController`)

- App icon + name + bundle ID + version + price
- "Download Latest" button (red, prominent)
- "View All Versions" button (secondary)
- App metadata section (ID, price)
- "Download Latest" → push DownloadViewController
- "View All Versions" → push VersionListViewController

### 4. Version List (`VersionListViewController`)

- App header (name + latest version)
- UITableView of all versions
- Each row: version string + release date + "GET" button
- Latest version highlighted
- Metadata fetched via partial ZIP reads (async, loaded progressively)
- Tap GET → push DownloadViewController with specific versionID

### 5. Download (`DownloadViewController`)

- App header (icon + name + version)
- Progress bar with percentage + byte count
- Step checklist:
  - License acquired ✓
  - Downloading IPA ⏳
  - Patching metadata ○
  - Sinf replicated ○
  - Ready ○
- Post-download action buttons:
  - **Install** — calls `RootExec.installIPA(path:)` via daemon
  - **Share** — UIActivityViewController (AirDrop, Files, etc.)
  - **Open in Files** — open containing directory

## Daemon Changes

### New command: `INSTALL_IPA`

Added to `handle_client()` in `BeerusDaemon.c`:

```c
else if (strncmp(buf, "INSTALL_IPA ", 12) == 0) {
    install_ipa(buf + 12, out, sizeof(out));
}
```

**`install_ipa` implementation:**
1. Verify file exists at given path
2. Try `appinst <path>` if available (common jailbreak tool)
3. Fallback: extract IPA → copy `.app` to `/Applications/` (rootful) or `/var/jb/Applications/` (rootless) → run `uicache -p <app_path>`
4. Return `ok: installed <app_name>` or `error: <reason>`

### Swift side (`RootExec.swift`)

```swift
static func installIPA(path: String) -> String? {
    send("INSTALL_IPA \(path)")
}
```

## File Structure

```
BEERUS Framework/Sources/Modules/AppStore/
├── Model/
│   ├── AppStoreAccount.swift
│   ├── AppStoreApp.swift
│   ├── DownloadResult.swift
│   └── VersionMetadata.swift
├── Service/
│   ├── AppStoreService.swift
│   ├── AppStoreCredentialManager.swift
│   ├── PlistPayload.swift
│   └── IPAProcessor.swift
├── View/
│   ├── SearchResultCell.swift
│   └── VersionCell.swift
└── ViewController/
    ├── AppStoreLoginViewController.swift
    ├── AppStoreSearchViewController.swift
    ├── AppDetailViewController.swift
    ├── VersionListViewController.swift
    └── DownloadViewController.swift
```

### Modified Existing Files

| File | Change |
|------|--------|
| `TabOption.swift` | Add `.appStore` case with icon `"cart"` (SF Symbol: `cart.fill`) |
| `ContainerViewController.swift` | Map `.appStore` → Login or Search based on stored credentials |
| `RootExec.swift` | Add `installIPA(path:)` method |
| `Daemon/BeerusDaemon.c` | Add `INSTALL_IPA` handler + `install_ipa()` function |

### No New Dependencies

All implemented with native frameworks:
- `Foundation` — URLSession, PropertyListSerialization, JSONSerialization
- `Security` — SecItem* (Keychain)
- Existing `ZipArchive.swift` — reused for IPA ZIP operations

## Error Handling

| Error | Behavior |
|-------|----------|
| Token expired (2034/2042) | Auto re-login via bag endpoint, retry operation |
| License required (9610) | Auto purchase if free, then retry download |
| 2FA required | Show 2FA field on login screen, prompt user |
| Account disabled | Show error, suggest checking Apple ID |
| Paid app | Reject with "paid apps not supported" message |
| Network failure | Show error with retry button |
| Download interrupted | Resume supported via HTTP Range header |
| Install failure | Show daemon error message to user |

## Storage Paths

- **Downloaded IPAs**: `/var/mobile/Documents/BEERUS/IPAs/` — created on first download
- **Temp files**: `FileManager.default.temporaryDirectory` — cleaned after patching
- **Cookies**: `HTTPCookieStorage.shared` — iOS manages persistence natively
- **Credentials**: iOS Keychain, service `io.hakaisecurity.beerus.appstore`

## IPA Filename Convention

Format: `{BundleID}_{AppID}_{Version}.ipa` (matches ipatool convention)
Example: `net.whatsapp.WhatsApp_310633997_24.10.80.ipa`

## Security Considerations

- Password stored in iOS Keychain (encrypted at rest by iOS)
- Password transmitted only to Apple's auth endpoint (HTTPS)
- No password logging even in verbose mode
- Daemon verifies client identity before executing INSTALL_IPA (existing CDHash + path verification)
