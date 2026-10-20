# Builds tideSI-<version>.msix (repository root) from PyInstaller's "dist\tideSI"
# folder, for upload to Microsoft Partner Center. The package is NOT signed: the
# Store signs it on submission, so it cannot be double-clicked to install.
# Used by .github/workflows/windows.yml; run from the repository root after
#   pyinstaller --noconfirm hosts/windows/tidesi.spec
#
#   hosts/windows/build-msix.ps1 -Version 4.0.0 `
#     -IdentityName 12345Muddyblack.tideSI -Publisher "CN=XXXXXXXX-..." -PublisherDisplayName Muddyblack
#
# The three identity values are on Partner Center → the app → Product management
# → Product identity. Without them, placeholders make a package that only checks
# the build works (CI does this on every push).
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$IdentityName = "Muddyblack.tideSI",
    [string]$Publisher = "CN=Muddyblack",
    [string]$PublisherDisplayName = "Muddyblack"
)
$ErrorActionPreference = "Stop"

if ($Version -notmatch '^\d+\.\d+\.\d+') { throw "Expected a version such as 4.0.0, got '$Version'" }
$msixVersion = "$($Matches[0]).0"

# makeappx.exe ships with the Windows SDK, which GitHub's Windows runners have.
$makeappx = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\makeappx.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $makeappx) { throw "makeappx.exe (Windows 10/11 SDK) was not found." }

$stage = "dist\msix"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path "$stage\Assets" | Out-Null
Copy-Item "dist\tideSI" "$stage\tideSI" -Recurse

# Tile and store logos, drawn from the app icon (Pillow comes with PyInstaller's build step).
$logos = @'
from PIL import Image
icon = Image.open("assets/icon.png").convert("RGBA")
def tile(name, w, h, scale=0.8):
    side = int(min(w, h) * scale)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glyph = icon.resize((side, side), Image.LANCZOS)
    canvas.paste(glyph, ((w - side) // 2, (h - side) // 2), glyph)
    canvas.save(f"dist/msix/Assets/{name}.png")
tile("Square44x44Logo", 44, 44, 1.0)
tile("StoreLogo", 50, 50, 1.0)
tile("Square150x150Logo", 150, 150)
tile("Wide310x150Logo", 310, 150)
'@
$logos | python -
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

(Get-Content "hosts\windows\msix\AppxManifest.xml.in" -Raw).
    Replace("@NAME@", $IdentityName).
    Replace("@PUBLISHER@", $Publisher).
    Replace("@PUBLISHER_DISPLAY@", $PublisherDisplayName).
    Replace("@VERSION@", $msixVersion) |
    Set-Content "$stage\AppxManifest.xml" -Encoding utf8

$out = "tideSI-$Version.msix"
if (Test-Path $out) { Remove-Item $out }
& $makeappx.FullName pack /d $stage /p $out /o
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
