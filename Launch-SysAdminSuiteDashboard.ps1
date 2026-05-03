#Requires -Version 5.1
<#
.SYNOPSIS
    Launches the SysAdminSuite web dashboard with a Harold splash screen.
.DESCRIPTION
    Starts server.py in the background, shows the Harold meme splash while the
    server initialises, then opens the default browser and closes the splash.
    After launch a system-tray icon keeps the server alive and lets the user
    stop it cleanly.  If server.py crashes after launch a balloon notification
    is shown.
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

$trayIcon16 = $null   # will hold a 16×16 icon bitmap for the tray

if (Test-Path -LiteralPath $haroldImage) {
    $splashImg    = [System.Drawing.Image]::FromFile($haroldImage)
    $picBox.Image = $splashImg

    $iconBmp = New-Object System.Drawing.Bitmap($splashImg, 64, 64)
    try { $splash.Icon = [System.Drawing.Icon]::FromHandle($iconBmp.GetHicon()) } catch {}

    # Build a 16×16 version for the tray
    try { $trayIcon16 = [System.Drawing.Icon]::FromHandle(
            (New-Object System.Drawing.Bitmap($splashImg, 16, 16)).GetHicon()) } catch {}
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

$deadline         = [System.DateTime]::Now.AddSeconds($timeoutSec)
$serverProc       = $null
$script:launchSucceeded = $false

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
        $script:launchSucceeded = $true
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

# -----------------------------------------------------------------------
# If the server was never started (pre-flight error path) just exit now.
# If startup timed out, kill any orphaned server process and exit cleanly.
# -----------------------------------------------------------------------
if ($null -eq $serverProc) { exit 0 }

if (-not $script:launchSucceeded) {
    try { if (-not $serverProc.HasExited) { $serverProc.Kill() } } catch {}
    exit 1
}

# -----------------------------------------------------------------------
# System-tray phase — keep PowerShell alive and own the server lifetime.
# -----------------------------------------------------------------------

# Fallback icon if no image was found: a plain blue square
if ($null -eq $trayIcon16) {
    $bmp = New-Object System.Drawing.Bitmap(16, 16)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::SteelBlue)
    $g.Dispose()
    try { $trayIcon16 = [System.Drawing.Icon]::FromHandle($bmp.GetHicon()) } catch {}
}

# Context menu
$ctxMenu     = New-Object System.Windows.Forms.ContextMenuStrip
$menuOpen    = New-Object System.Windows.Forms.ToolStripMenuItem('Open Dashboard')
$menuStop    = New-Object System.Windows.Forms.ToolStripMenuItem('Stop Dashboard')
$ctxMenu.Items.Add($menuOpen) | Out-Null
$ctxMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$ctxMenu.Items.Add($menuStop) | Out-Null

# NotifyIcon
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon             = $trayIcon16
$notify.Text             = 'SysAdminSuite Dashboard'
$notify.ContextMenuStrip = $ctxMenu
$notify.Visible          = $true

# Show a balloon so the user knows where the icon is
$notify.BalloonTipTitle = 'SysAdminSuite Dashboard'
$notify.BalloonTipText  = 'Server is running. Right-click this icon to stop.'
$notify.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
$notify.ShowBalloonTip(4000)

# Hidden host form — keeps the WinForms message loop alive
$host_form = New-Object System.Windows.Forms.Form
$host_form.FormBorderStyle = 'None'
$host_form.WindowState     = 'Minimized'
$host_form.ShowInTaskbar   = $false
$host_form.Size            = New-Object System.Drawing.Size(1, 1)

# Helper: clean shutdown
$script:shuttingDown = $false
function Stop-Dashboard {
    if ($script:shuttingDown) { return }
    $script:shuttingDown = $true
    $monitorTimer.Stop()
    $notify.Visible = $false
    $notify.Dispose()
    try {
        if (-not $serverProc.HasExited) { $serverProc.Kill() }
    } catch {}
    $host_form.Close()
}

# "Open Dashboard" action
$menuOpen.Add_Click({ Start-Process $dashboardUrl })

# "Stop Dashboard" action
$menuStop.Add_Click({ Stop-Dashboard })

# Double-click tray icon → open dashboard
$notify.Add_DoubleClick({ Start-Process $dashboardUrl })

# Monitor timer — checks every 3 seconds whether server.py is still alive
$monitorTimer = New-Object System.Windows.Forms.Timer
$monitorTimer.Interval = 3000
$monitorTimer.Add_Tick({
    if ($script:shuttingDown) { return }
    try {
        if ($serverProc.HasExited) {
            $monitorTimer.Stop()
            $notify.BalloonTipTitle = 'SysAdminSuite — Server stopped'
            $notify.BalloonTipText  = 'server.py exited unexpectedly. The dashboard is no longer available.'
            $notify.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Error
            $notify.ShowBalloonTip(8000)

            # Disable "Open Dashboard" since it won't work any more
            $menuOpen.Enabled = $false
            $menuStop.Text    = 'Exit'
        }
    } catch {}
})
$monitorTimer.Start()

$host_form.ShowDialog() | Out-Null

# Ensure server is killed if host_form was closed by other means
Stop-Dashboard
