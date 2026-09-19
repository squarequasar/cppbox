# CppBox Launcher
# made by squarequasar
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function T {
    param([string]$Base64)
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64))
}

$Internal = Split-Path -Parent $PSScriptRoot
$Root = Split-Path -Parent $Internal
$Workspace = Join-Path $Root 'workspace'
$SetupScript = Join-Path $PSScriptRoot 'Setup-CppBox.ps1'
$App = Join-Path $Internal 'app'
$Toolchain = Join-Path $Internal 'toolchain'
$VsCodeData = Join-Path $App 'vscode\data'
$Logs = Join-Path $Internal 'logs'
$LauncherLog = Join-Path $Logs 'launcher_error.log'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null

$Cream = [System.Drawing.Color]::FromArgb(243, 234, 220)
$CreamLight = [System.Drawing.Color]::FromArgb(255, 248, 235)
$Black = [System.Drawing.Color]::FromArgb(11, 11, 12)
$Ink = [System.Drawing.Color]::FromArgb(17, 17, 17)
$Muted = [System.Drawing.Color]::FromArgb(111, 103, 95)
$Red = [System.Drawing.Color]::FromArgb(196, 54, 49)
$Green = [System.Drawing.Color]::FromArgb(49, 168, 106)
$Gray = [System.Drawing.Color]::FromArgb(122, 113, 104)

function Find-File {
    param([string]$RootDir, [string]$FileName)
    if (-not (Test-Path -LiteralPath $RootDir)) { return $null }
    $found = Get-ChildItem -LiteralPath $RootDir -Filter $FileName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Get-CppBoxState {
    $code = Find-File (Join-Path $App 'vscode') 'Code.exe'
    $gpp = Find-File $Toolchain 'g++.exe'
    $extensionRoot = Join-Path $VsCodeData 'extensions'
    $extension = $false
    if (Test-Path -LiteralPath $extensionRoot) {
        $extension = [bool](Get-ChildItem -LiteralPath $extensionRoot -Directory -Filter 'ms-vscode.cpptools-extension-pack*' -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not $extension) {
            $extension = [bool](Get-ChildItem -LiteralPath $extensionRoot -Directory -Filter 'ms-vscode.cpptools*' -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
    }

    [pscustomobject]@{
        CodeReady = [bool]$code
        CompilerReady = [bool]$gpp
        ExtensionReady = $extension
        Ready = ([bool]$code -and [bool]$gpp)
    }
}

function Invoke-HiddenPowerShell {
    param([string[]]$Arguments)
    $allArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass') + $Arguments
    $escaped = $allArguments | ForEach-Object {
        '"' + ($_ -replace '"', '\"') + '"'
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = ($escaped -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $process = [System.Diagnostics.Process]::Start($psi)
    $process.WaitForExit()
    return $process.ExitCode
}

function Invoke-HiddenPowerShellWithProgress {
    param([string[]]$Arguments, [string]$ActionText)
    $progressFile = Join-Path $Logs 'launcher_progress.txt'
    Remove-Item -LiteralPath $progressFile -Force -ErrorAction SilentlyContinue
    $Arguments = $Arguments + @('-ProgressFile', $progressFile)
    $allArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass') + $Arguments
    $escaped = $allArguments | ForEach-Object {
        '"' + ($_ -replace '"', '\"') + '"'
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = ($escaped -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $process = [System.Diagnostics.Process]::Start($psi)

    $lastPercent = -1
    while (-not $process.HasExited) {
        if (Test-Path -LiteralPath $progressFile) {
            $rawProgress = Get-Content -LiteralPath $progressFile -ErrorAction SilentlyContinue | Select-Object -Last 1
            if ($rawProgress -match '^(\d+)\|') {
                $lastPercent = [int]$Matches[1]
            }
        }
        if ($lastPercent -ge 0) {
            $mainButton.Text = ('{0} {1}%' -f $ActionText, $lastPercent)
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 250
    }
    if (Test-Path -LiteralPath $progressFile) {
        $rawProgress = Get-Content -LiteralPath $progressFile -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($rawProgress -match '^(\d+)\|') {
            $lastPercent = [int]$Matches[1]
        }
    }
    $mainButton.Text = ('{0} 100%' -f $ActionText)
    [System.Windows.Forms.Application]::DoEvents()
    Remove-Item -LiteralPath $progressFile -Force -ErrorAction SilentlyContinue
    return $process.ExitCode
}

function Reset-CppBox {
    foreach ($path in @(
        (Join-Path $Internal 'app'),
        (Join-Path $Internal 'toolchain'),
        (Join-Path $Workspace '.vscode')
    )) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $workspaceFile = Join-Path $Workspace 'cppbox.code-workspace'
    if (Test-Path -LiteralPath $workspaceFile) {
        Remove-Item -LiteralPath $workspaceFile -Force -ErrorAction SilentlyContinue
    }
}

function New-Label {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [System.Drawing.Font]$Font,
        [System.Drawing.Color]$Color
    )
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($W, $H)
    $label.Font = $Font
    $label.ForeColor = $Color
    $label.BackColor = [System.Drawing.Color]::Transparent
    $label
}

function New-Button {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [bool]$Primary = $false
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($W, $H)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    if ($Primary) {
        $button.FlatAppearance.BorderSize = 0
    } else {
        $button.FlatAppearance.BorderSize = 2
    }
    $button.FlatAppearance.BorderColor = $Ink
    $fontSize = if ($Primary) { 14 } else { 10 }
    $button.Font = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', $fontSize, ([System.Drawing.FontStyle]::Bold)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    if ($Primary) {
        $button.BackColor = $Ink
        $button.ForeColor = $CreamLight
    } else {
        $button.BackColor = $CreamLight
        $button.ForeColor = $Ink
    }
    $button
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'CppBox'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(664, 356)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.MaximizeBox = $false
$form.BackColor = $Cream

$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(0, 0)
$panel.Size = New-Object System.Drawing.Size(664, 356)
$panel.BackColor = $Cream
$form.Controls.Add($panel)

$script:Dragging = $false
$script:DragOffset = New-Object System.Drawing.Point(0, 0)
function Enable-Drag {
    param($Control)
    $Control.Add_MouseDown({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:Dragging = $true
            $script:DragOffset = New-Object System.Drawing.Point($e.X, $e.Y)
        }
    })
    $Control.Add_MouseMove({
        param($sender, $e)
        if ($script:Dragging) {
            $screenPoint = $sender.PointToScreen((New-Object System.Drawing.Point($e.X, $e.Y)))
            $form.Location = New-Object System.Drawing.Point(($screenPoint.X - $script:DragOffset.X), ($screenPoint.Y - $script:DragOffset.Y))
        }
    })
    $Control.Add_MouseUp({
        param($sender, $e)
        $script:Dragging = $false
    })
    $Control.Add_MouseLeave({
        $script:Dragging = $false
    })
}
Enable-Drag $panel

$titleFont = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 28, ([System.Drawing.FontStyle]::Bold)
$subtitleFont = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 10
$statusFont = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 12, ([System.Drawing.FontStyle]::Bold)
$smallFont = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 9
$closeFont = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 16

$closeButton = New-Label 'x' 626 12 24 24 $closeFont $Ink
$closeButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$closeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$closeButton.Add_Click({ $form.Close() })
$panel.Controls.Add($closeButton)

$title = New-Label 'CppBox' 54 48 260 62 $titleFont $Ink
$panel.Controls.Add($title)
Enable-Drag $title

$underline = New-Object System.Windows.Forms.Panel
$underline.Location = New-Object System.Drawing.Point(58, 108)
$underline.Size = New-Object System.Drawing.Size(118, 5)
$underline.BackColor = $Red
$panel.Controls.Add($underline)

$subtitle = New-Label 'portable C++ workspace for Windows' 57 126 360 30 $subtitleFont $Muted
$panel.Controls.Add($subtitle)
Enable-Drag $subtitle

$signature = New-Label (T 'bWFkZSBieSBzcXVhcmVxdWFzYXI=') 526 262 100 40 $smallFont $Muted
$signature.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$panel.Controls.Add($signature)

$statusDot = New-Label (T '4peP') 520 62 24 32 (New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 18, ([System.Drawing.FontStyle]::Bold)) $Gray
$panel.Controls.Add($statusDot)

$statusText = New-Label (T '0L/RgNC+0LLQtdGA0Y/Rjg==') 550 68 100 30 $statusFont $Ink
$panel.Controls.Add($statusText)

$mainButton = New-Button (T '0J7RgtC60YDRi9GC0YwgVlMgQ29kZQ==') 54 176 556 70 $true
$panel.Controls.Add($mainButton)

$folderButton = New-Button (T '0J/QsNC/0LrQsCDRgSDQutC+0LTQvtC8') 54 262 130 40
$repairButton = New-Button (T '0J/QvtGH0LjQvdC40YLRjA==') 202 262 130 40
$panel.Controls.AddRange(@($folderButton, $repairButton))

$busyLabel = New-Label '' 54 252 556 22 $smallFont $Muted
$panel.Controls.Add($busyLabel)

$script:IsBusy = $false

function Set-Busy {
    param([bool]$Busy, [string]$Text = '', [string]$MainText = '')
    $script:IsBusy = $Busy
    foreach ($control in @($folderButton, $repairButton)) {
        $control.Enabled = -not $Busy
    }
    $mainButton.Enabled = $true
    $busyLabel.Text = $Text
    if ($MainText -ne '') {
        $mainButton.Text = $MainText
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Refresh-State {
    $state = Get-CppBoxState
    if ($state.Ready) {
        $statusDot.ForeColor = $Green
        $statusText.Text = T '0LPQvtGC0L7Qsg=='
        $mainButton.Text = T '0J7RgtC60YDRi9GC0YwgVlMgQ29kZQ=='
    } else {
        $statusDot.ForeColor = $Red
        $statusText.Text = T '0L3QtSDQs9C+0YLQvtCy'
        $mainButton.Text = T '0KPRgdGC0LDQvdC+0LLQuNGC0YwgQ3BwQm94'
    }
    return $state
}

function Install-CppBox {
    Set-Busy $true '' ((T '0YPRgdGC0LDQvdCw0LLQu9C40LLQsNGO') + ' 0%')
    try {
        $exit = Invoke-HiddenPowerShellWithProgress -Arguments @('-File', $SetupScript, '-NoOpen') -ActionText (T '0YPRgdGC0LDQvdCw0LLQu9C40LLQsNGO')
        if ($exit -ne 0) {
            [System.Windows.Forms.MessageBox]::Show((T '0KPRgdGC0LDQvdC+0LLQutCwINC90LUg0LfQsNC60L7QvdGH0LjQu9Cw0YHRjCDQvdC+0YDQvNCw0LvRjNC90L4uINCd0LDQttC80LggItCf0L7Rh9C40L3QuNGC0YwiINC4INC/0L7Qv9GA0L7QsdGD0Lkg0LXRidGRINGA0LDQty4='), 'CppBox', 'OK', 'Warning') | Out-Null
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'CppBox', 'OK', 'Error') | Out-Null
    }
    finally {
        Set-Busy $false
        Refresh-State | Out-Null
    }
}

function Open-CppBox {
    if ($script:IsBusy) { return }
    $state = Refresh-State
    if (-not $state.Ready) {
        Install-CppBox
        return
    }
    Set-Busy $true '' (T '0L7RgtC60YDRi9Cy0LDRjg==')
    try {
        $exit = Invoke-HiddenPowerShell @('-File', $SetupScript, '-OpenOnly')
        if ($exit -ne 0) {
            [System.Windows.Forms.MessageBox]::Show((T '0J3QtSDQv9C+0LvRg9GH0LjQu9C+0YHRjCDQvtGC0LrRgNGL0YLRjCBWUyBDb2RlLiDQndCw0LbQvNC4ICLQn9C+0YfQuNC90LjRgtGMIiDQuCDQv9C+0L/RgNC+0LHRg9C5INC10YnRkSDRgNCw0Lcu'), 'CppBox', 'OK', 'Warning') | Out-Null
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'CppBox', 'OK', 'Error') | Out-Null
    }
    finally {
        Set-Busy $false
        Refresh-State | Out-Null
    }
}

$mainButton.Add_Click({ if (-not $script:IsBusy) { Open-CppBox } })
$folderButton.Add_Click({
    if ($script:IsBusy) { return }
    New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
    Start-Process explorer.exe -ArgumentList "`"$Workspace`""
})
$repairButton.Add_Click({
    if ($script:IsBusy) { return }
    $answer = [System.Windows.Forms.MessageBox]::Show((T '0KHQsdGA0L7RgdC40YLRjCDQstC90YPRgtGA0LXQvdC90Y7RjiDRg9GB0YLQsNC90L7QstC60YMgQ3BwQm94INC4INC/0L7RgdGC0LDQstC40YLRjCDQt9Cw0L3QvtCy0L4/'), 'CppBox', 'YesNo', 'Question')
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        Set-Busy $true '' (T '0YfQuNC90Y4=')
        try {
            Reset-CppBox
            Set-Busy $false
            Install-CppBox
        }
        catch {
            Set-Busy $false
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'CppBox', 'OK', 'Error') | Out-Null
        }
    }
})

$form.Add_Shown({ Refresh-State | Out-Null })
[System.Windows.Forms.Application]::EnableVisualStyles()
try {
    [void]$form.ShowDialog()
}
catch {
    $_ | Out-String | Set-Content -LiteralPath $LauncherLog -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'CppBox', 'OK', 'Error') | Out-Null
    exit 1
}
