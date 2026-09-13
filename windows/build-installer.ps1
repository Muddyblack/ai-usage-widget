# Builds AI-Usage-Setup-<version>.exe (repository root) from PyInstaller's
# "dist\AI Usage" folder with Inno Setup — see windows/installer.iss. Used by
# .github/workflows/windows.yml, which release.yml also runs for a tag; run it
# from the repository root after
#   pyinstaller --noconfirm windows/ai-usage.spec
#
#   windows/build-installer.ps1 -Version 2.4.0
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = "Stop"

# ISCC.exe of the newest Inno Setup there is (6.3 or later: installer.iss uses
# x64compatible) — on PATH, or wherever its installer put it.
function Find-Iscc {
    $onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $found = foreach ($root in ${env:ProgramFiles(x86)}, $env:ProgramFiles, "$env:LOCALAPPDATA\Programs") {
        if ($root) { Get-Item -Path (Join-Path $root "Inno Setup *\ISCC.exe") -ErrorAction SilentlyContinue }
    }
    return ($found | Sort-Object FullName -Descending | Select-Object -First 1).FullName
}

# GitHub's Windows runners may ship Inno Setup; install it where they do not.
$iscc = Find-Iscc
if (-not $iscc) {
    choco install innosetup -y --no-progress | Out-Null
    $iscc = Find-Iscc
}
if (-not $iscc) { throw "Inno Setup's ISCC.exe was not found, and installing it with Chocolatey did not help." }
Write-Output "Using $iscc"

# Inno Setup wants an .ico; the repository has the PNG (Pillow comes with the
# PyInstaller build step).
python -c "from PIL import Image; Image.open('package/icon.png').convert('RGBA').save('dist/ai-usage.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $iscc "/DAppVersion=$Version" "windows\installer.iss"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
