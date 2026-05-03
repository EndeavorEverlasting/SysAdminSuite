#Requires -Version 5.1
<#
.SYNOPSIS
    Launches the SysAdminSuite web dashboard with a Harold splash screen.
.DESCRIPTION
    Starts server.py in the background, shows the Harold meme splash while the
    server initialises, then opens the default browser and closes the splash.
    If server.py or Python cannot be found the splash shows an immediate error.
    If the server does not respond within the timeout the splash shows an error
    message and exits cleanly.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$repoRoot     = $PSScriptRoot
$serverPort   = 5000
$dashboardUrl = "http://localhost:$serverPort"
$serverScript = Join-Path $repoRoot 'server.py'
$haroldImage  = Join-Path $repoRoot 'happy-sad-guy-meme-6-206777197.jpg'
$timeoutSec   = 15
$pollMs       = 300

# -- Build the splash form --
$splash = New-Object System.Windows.Forms.Form
$splash.FormBorderStyle = 'None'
$splash.StartPosition   = 'CenterScreen'
$splash.TopMost         = $true
$splash.BackColor       = [System.Drawing.Color]::Black
$splash.Size            = New-Object System.Drawing.Size(480, 420)
$splash.ShowInTaskbar   = $false

$picBox = New-Object System.Windows.Forms.PictureBox
$picBox.Dock     = 'Fill'
$picBox.SizeMode = 'Zoom'

if (Test-Path -LiteralPath $haroldImage) {
    $splashImg    = [System.Drawing.Image]::FromFile($haroldImage)
    $picBox.Image = $splashImg

    $iconBmp = New-Object System.Drawing.Bitmap($splashImg, 64, 64)
    try { $splash.Icon = [System.Drawing.Icon]::FromHandle($iconBmp.GetHicon()) } catch {}
}
$splash.Controls.Add($picBox)

$splashLabel = New-Object System.Windows.Forms.Label
$splashLabel.Text      = 'SysAdminSuite - Loading...'
$splashLabel.Font      = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
$splashLabel.ForeColor = [System.Drawing.Color]::White
$splashLabel.BackColor = [System.Drawing.Color]::FromArgb(180, 0, 0, 0)
$splashLabel.TextAlign = 'MiddleCenter'
$splashLabel.Dock      = 'Bottom'
$splashLabel.Height    = 38
$splash.Controls.Add($splashLabel)
$splashLabel.BringToFront()

# Helper: show an error on the splash label then auto-close after $delaySec seconds
function Show-SplashError {
    param([string]$Message, [int]$DelaySec = 3)
    $splashLabel.Text      = $Message
    $splashLabel.BackColor = [System.Drawing.Color]::FromArgb(200, 140, 0, 0)
    $splash.Refresh()
    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = $DelaySec * 1000
    $t.Add_Tick({ $t.Stop(); $splash.Close() })
    $t.Start()
}

# -- Pre-flight checks: fail fast if server.py or Python are missing --
$startError = $null

if (-not (Test-Path -LiteralPath $serverScript)) {
    $startError = 'server.py not found — check installation'
}

$pythonExe = $null
if (-not $startError) {
    $pythonExe = if (Get-Command python  -ErrorAction SilentlyContinue) { 'python'  }
                 elseif (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' }
                 else { $null }

    if (-not $pythonExe) {
        $startError = 'Python not found — install Python and try again'
    }
}

# -- Timer that drives the poll loop on the UI thread --
$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = $pollMs

$deadline   = [System.DateTime]::Now.AddSeconds($timeoutSec)
$serverProc = $null

$pollTimer.Add_Tick({
    # Check whether our server is responding with HTTP 200
    $ready = $false
    try {
        $req = [System.Net.WebRequest]::Create($dashboardUrl)
        $req.Timeout = 800
        $resp = $req.GetResponse()
        $statusCode = [int]$resp.StatusCode
        $resp.Close()
        if ($statusCode -eq 200) { $ready = $true }
    } catch { }

    if ($ready) {
        $pollTimer.Stop()
        Start-Process $dashboardUrl
        $splash.Close()
        return
    }

    if ([System.DateTime]::Now -gt $deadline) {
        $pollTimer.Stop()
        Show-SplashError 'Failed to start — check server.py'
    }
})

# -- Start server or show immediate error --
if ($startError) {
    # Show error as soon as the splash is on screen (10 ms delay so ShowDialog renders first)
    $earlyTimer = New-Object System.Windows.Forms.Timer
    $earlyTimer.Interval = 10
    $earlyTimer.Add_Tick({
        $earlyTimer.Stop()
        Show-SplashError $startError
    })
    $earlyTimer.Start()
} else {
    $serverProc = Start-Process -FilePath $pythonExe `
                                -ArgumentList "`"$serverScript`"" `
                                -WorkingDirectory $repoRoot `
                                -WindowStyle Hidden `
                                -PassThru
    $pollTimer.Start()
}

$splash.ShowDialog() | Out-Null
$splash.Dispose()
