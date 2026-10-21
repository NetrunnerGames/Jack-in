---
name: jackin-release
description: >-
  Build-and-release workflow for the Jack-in Steam CEF plugin only (repo
  NetrunnerGames/Jack-in): zip packaging of plugin.json, backend, and public into
  plugin.zip, sha256 manifest sync, structured [+] / [-] changelog formatting,
  git commit + tag, and GitHub release upload of plugin.zip — used when the user
  explicitly requests a new Jack-in build/release.
---

# Jack-in Release Workflow

## 0. Scope

This workflow applies **only** to the Jack-in plugin repository (`C:\Users\Flynn\Projects\Jack-in`,
remote `NetrunnerGames/Jack-in`). It never touches DataJackUI version files
(`DataJackUIGui.csproj`, `build_release.ps1`), never touches IceBreaker native DLL files
(`version.dll`), and does not upload DataJackUI installer artifacts (`DataJackUI-win-Setup.zip`).
The sole release asset for Jack-in is `plugin.zip`.

---

## 1. Versioning Rules (Semantic Versioning)

Determine the appropriate version increment based on the nature of the changes:

* **Major Bump (`X.0.0`)**: Breaking architectural changes, complete frontend UI framework redesigns, or breaking RPC protocol shifts (e.g. `2.0.0`).
* **Minor / Sub Bump (`x.Y.0` or `x.Y`)**: New UI features, new themes, new backend RPC handlers, or new IPC bridge capabilities (e.g. `1.3`).
* **Patch Bump (`x.y.Z`)**: Bug fixes, styling adjustments, hot-reload tweaks, or edge-case handling (e.g. `1.2.1`).

### Component Cadence
* **Jack-in Plugin**:
  - Release tag: `v<Version>` (e.g. `v1.3`).
  - `plugin.json`: Update `"version"` property to match `<Version>`.
  - `installed.json`: Update `"Tag"` to `"v<Version>"` and `"ZipSha"` to the computed SHA-256 of `plugin.zip`.
  - Local AppData: Synchronize updated files to `%AppData%\DataJackUIGui\plugin\`.

---

## 2. Revision Tracking & Trigger

- Maintain a running log of all unreleased changes (`[+] added/changed`, `[-] removed`) during the session.
- **Do NOT publish releases automatically on every commit.**
- Execute the release packaging and GitHub publish **ONLY when the user explicitly requests "publish new build"** (or invokes `/jackin-release`).

---

## 3. GitHub Release Title & Body Formatting

Generate a dynamic, descriptive release title based on the primary focus of the changes, followed by the structured `[+]` / `[-]` changelog body:

### Release Title Format
`Release v<Version>: <Dynamic Category / Focus Summary>`

Examples:
- `Release v1.3: Inter-Process Communication Bridge & Zero-Restart Hot-Reload`
- `Release v1.2: Netrunner Glassmorphism UI Redesign`

### Release Body Format
```text
[+] Added / modified feature or bug fix detail
[+] Additional feature or enhancement
[-] Removed or deprecated feature
```

### Sensitive Information & Privacy Guidelines
- **Never include internal administrative roles, creator/owner mentions, specific user IDs, or sensitive authentication details** in commit messages, release titles, or release notes.
- Use clean, professional wording such as "hot-reload manifest synchronization" or "CEF store page integration".

---

## 4. Release Execution Procedure

1. **Changelog files** (Jack-in repo root `C:\Users\Flynn\Projects\Jack-in`, plain text):
   - `changelog.txt`: The `[+]` / `[-]` lines for this release.
   - `highlights.txt`: Bullet-point highlights.

2. **Sync Version & Package `plugin.zip`**:
   - Update `"version"` in `plugin.json` to `<Version>`.
   - Remove any previous `plugin.zip`.
   - Archive `plugin.json`, `backend`, and `public` into `plugin.zip`:
     ```powershell
     Remove-Item plugin.zip -Force -ErrorAction SilentlyContinue
     Compress-Archive -Path plugin.json, backend, public -DestinationPath plugin.zip
     ```
   - Calculate the SHA-256 hash of `plugin.zip`:
     ```powershell
     $hash = (Get-FileHash -Path plugin.zip -Algorithm SHA256).Hash.ToLowerInvariant()
     ```
   - Update `installed.json` with the new `"Tag"` and `"ZipSha"`:
     ```json
     {"Tag":"v<Version>","DllShas":{},"ZipSha":"<hash>","DisabledMillenniumEntries":null}
     ```
   - Sync files to local AppData directory (`%AppData%\DataJackUIGui\plugin\`):
     ```powershell
     Copy-Item plugin.json, installed.json, plugin.zip "$env:APPDATA\DataJackUIGui\plugin\" -Force
     Copy-Item backend\*, public\* "$env:APPDATA\DataJackUIGui\plugin\" -Recurse -Force
     ```

3. **Git Version Control**:
   - Stage repo files:
     ```powershell
     git add plugin.json installed.json backend public plugin.zip changelog.txt highlights.txt
     git commit -m "release: v<Version> - <Title>"
     git tag -a v<Version> -m "Release v<Version>: <Title>"
     git push origin main v<Version>
     ```

4. **GitHub Release Creation**:
   - Retrieve token via `git credential fill` if `gh` is unauthenticated:
     ```powershell
     $cred = ("protocol=https`nhost=github.com`n`n" | git credential fill)
     $env:GH_TOKEN = ($cred | Select-String "password=(.+)").Matches.Groups[1].Value.Trim()
     ```
   - Publish the release attaching **only** `plugin.zip`:
     ```powershell
     gh release create v<Version> plugin.zip --repo NetrunnerGames/Jack-in --title "Release v<Version>: <Title>" --notes-file changelog.txt
     ```

5. **Verification**:
   - Verify the GitHub release with `gh release view v<Version> --repo NetrunnerGames/Jack-in --json assets,tagName,name`.
   - Confirm it lists exactly one asset, `plugin.zip`, matching the generated file size and SHA-256.
