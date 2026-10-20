# Microsoft Store

The Store build is the same PyInstaller bundle as the other Windows downloads,
wrapped as an MSIX by `hosts/windows/build-msix.ps1`. CI builds
`tideSI-<version>.msix` on every Windows run and keeps it in the `tidesi-windows`
artifact. It is **unsigned on purpose**: Microsoft signs it when you submit it,
so it cannot be installed by double-click. winget, Scoop and the GitHub
downloads keep using the Inno `tideSI-Setup-<version>.exe` and the ZIP.

## One-time setup

1. Open an individual developer account at <https://partner.microsoft.com/dashboard>
   (free for individuals).
2. Create a new app and reserve the name **tideSI**.
3. Under *Product management → Product identity* copy three values and save
   them as repository variables (Settings → Secrets and variables → Actions →
   Variables):

   | Partner Center | Repository variable |
   | --- | --- |
   | Package/Identity/Name | `STORE_IDENTITY_NAME` |
   | Package/Identity/Publisher | `STORE_PUBLISHER` |
   | Package/Properties/PublisherDisplayName | `STORE_PUBLISHER_DISPLAY_NAME` |

4. Pricing: *Paid*, price tier of your choice, no free trial (the free builds
   are the trial). Markets: all.
5. Age rating questionnaire, privacy policy URL (a page stating that tideSI
   reads local AI-tool credentials, talks only to the providers' own APIs, and
   sends nothing to the author), category *Developer tools* or *Productivity*.
6. In the certification notes explain that the app reads the credential files of
   AI CLIs the user already has installed, and calls each provider's usage API
   with them, so a reviewer is not surprised.

## Each release

1. Cut the release as usual (`make tag`). CI attaches the other files to the
   GitHub release.
2. Download `tideSI-<version>.msix` from the Windows workflow run's
   `tidesi-windows` artifact (the identity variables must be set before that run).
3. Partner Center → the app → *Start update* → *Packages* → upload the MSIX →
   *Submit*. Certification usually takes under a few days.

## Known limits of the MSIX

- **Start with Windows** uses a `windows.startupTask` (`hosts/windows/startuptask.py`)
  instead of the Run key, which an MSIX virtualizes. Windows keeps a task the
  user switched off in Settings → Apps → Startup off until they switch it back on.
- **Settings and history** are redirected to the package's private
  `%LOCALAPPDATA%\Packages\...` folder, so they are separate from the
  Inno/Scoop install.
- Not yet tested on a real machine: install the Store build once on Windows
  with `Add-AppxPackage` after signing it with a test certificate.
