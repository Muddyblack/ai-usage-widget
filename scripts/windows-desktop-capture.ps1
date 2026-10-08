# A real desktop capture of the app, tray and optional taskbar pill. Offscreen
# renders cannot exercise Explorer, DWM or native window placement.
param([Parameter(Mandatory = $true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# A fresh demo config: no provider calls, no runner credentials/settings.
@{ floatingPill = $true; windowsTaskbar = $true } | ConvertTo-Json |
    Set-Content -Encoding utf8 $env:AI_USAGE_CONFIG
$process = Start-Process python -ArgumentList @('hosts/desktop/app.py', '--demo') -PassThru `
    -RedirectStandardOutput "$OutputDirectory/desktop.stdout.log" `
    -RedirectStandardError "$OutputDirectory/desktop.stderr.log"
try {
    Start-Sleep -Seconds 20
    if ($process.HasExited) { throw "App exited before capture ($($process.ExitCode))" }
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
        $bitmap.Save("$OutputDirectory/desktop-windows.png", [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    Get-Content "$OutputDirectory/desktop.stderr.log" -ErrorAction SilentlyContinue
}
