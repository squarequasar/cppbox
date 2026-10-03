param(
    [switch]$OpenOnly,
    [switch]$NoOpen,
    [string]$ProgressFile = '',
    [string]$CancelFile = ''
)

# CppBox setup engine
# made by squarequasar
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Internal = Split-Path -Parent $PSScriptRoot
$Root = Split-Path -Parent $Internal
$Cache = Join-Path $Internal 'cache'
$App = Join-Path $Internal 'app'
$VsCode = Join-Path $App 'vscode'
$VsCodeData = Join-Path $VsCode 'data'
$Toolchain = Join-Path $Internal 'toolchain'
$Workspace = Join-Path $Root 'workspace'
$Build = Join-Path $Internal 'build'
$Logs = Join-Path $Internal 'logs'
$Log = Join-Path $Logs ("setup_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

$VsCodeZip = Join-Path $Cache 'vscode-win32-x64-archive-stable.zip'
$WinLibsZip = Join-Path $Cache 'winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip'

$VsCodeUrl = 'https://update.code.visualstudio.com/latest/win32-x64-archive/stable'
$WinLibsUrl = 'https://github.com/brechtsanders/winlibs_mingw/releases/download/16.2.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.2.0-mingw-w64ucrt-14.0.0-r1.zip'
$WinLibsSha256 = 'c1f52294597c0b73786b2a78eb5d176d89226d2f21875eab75e783a8b1cefcc4'

function Say {
    param([string]$Text)
    Write-Host $Text
    Add-Content -LiteralPath $Log -Value $Text -Encoding UTF8
}

function Set-Progress {
    param(
        [int]$Percent,
        [string]$Stage,
        [long]$BytesReceived = 0,
        [long]$BytesTotal = 0
    )
    Assert-NotCancelled
    if ($ProgressFile) {
        $parent = Split-Path -Parent $ProgressFile
        if ($parent) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        ('{0}|{1}|{2}|{3}' -f $Percent, $Stage, $BytesReceived, $BytesTotal) | Set-Content -LiteralPath $ProgressFile -Encoding ASCII
    }
}

function Ensure-Dirs {
    foreach ($dir in @($Cache, $App, $Toolchain, $Workspace, $Build, $Logs)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

function Test-ZipFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    if ((Get-Item -LiteralPath $Path).Length -lt 1048576) {
        return $false
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $header = New-Object byte[] 4
        [void]$stream.Read($header, 0, 4)
        if (-not ($header[0] -eq 0x50 -and $header[1] -eq 0x4B)) {
            return $false
        }
        $stream.Position = 0
        $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            [void]$zip.Entries.Count
            return $true
        }
        finally {
            $zip.Dispose()
        }
    }
    catch {
        return $false
    }
    finally {
        $stream.Close()
    }
}

function Assert-NotCancelled {
    if ($CancelFile -and [IO.File]::Exists($CancelFile)) {
        throw [OperationCanceledException]::new('Installation cancelled.')
    }
}

function Download-File {
    param([string]$Url, [string]$OutFile, [string]$Name)
    Assert-NotCancelled
    if (Test-ZipFile $OutFile) { Say "[OK] Cached $Name"; return }
    $partial = $OutFile + '.partial'
    $bits = $null
    $client = $null
    try {
        $downloaded = $false
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            try {
                $bits = Start-BitsTransfer -Source $Url -Destination $partial -Asynchronous -Priority Foreground -DisplayName "CppBox: $Name" -ErrorAction Stop
                $stalled = [Diagnostics.Stopwatch]::StartNew()
                $lastBytes = 0
                while ($bits.JobState -ne 'Transferred') {
                    Assert-NotCancelled
                    if ($bits.JobState -in @('Error', 'Cancelled', 'Suspended')) { throw "BITS: $($bits.JobState)" }
                    $received = [long]$bits.BytesTransferred
                    $total = if ($bits.BytesTotal -le [long]::MaxValue) { [long]$bits.BytesTotal } else { 0 }
                    if ($received -ne $lastBytes) { $stalled.Restart(); $lastBytes = $received }
                    if ($stalled.Elapsed.TotalSeconds -gt 30) { throw 'BITS stalled.' }
                    $percent = if ($total -gt 0) { [int][math]::Min(99, [math]::Floor($received * 100.0 / $total)) } else { 0 }
                    Set-Progress $percent ("download:$Name") $received $total
                    Start-Sleep -Milliseconds 150
                    $bits = Get-BitsTransfer -JobId $bits.JobId -ErrorAction Stop
                }
                Assert-NotCancelled
                Complete-BitsTransfer -BitsJob $bits -ErrorAction Stop
                $bits = $null
                $downloaded = $true
            } catch [OperationCanceledException] { throw }
            catch {
                if ($bits) { Remove-BitsTransfer -BitsJob $bits -Confirm:$false -ErrorAction SilentlyContinue; $bits = $null }
                Assert-NotCancelled
                Say "[..] Switching downloader: $($_.Exception.Message)"
            }
        }
        if (-not $downloaded) {
            if (-not ('CppBoxTransfer' -as [type])) {
                Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Threading;
using System.Threading.Tasks;
public sealed class CppBoxTransfer : IDisposable {
    readonly WebClient client = new WebClient();
    long received, total;
    Task active;
    public long Received { get { return Interlocked.Read(ref received); } }
    public long Total { get { return Math.Max(0, Interlocked.Read(ref total)); } }
    public CppBoxTransfer() {
        client.DownloadProgressChanged += (s, e) => {
            Interlocked.Exchange(ref received, e.BytesReceived);
            Interlocked.Exchange(ref total, e.TotalBytesToReceive);
        };
    }
    public Task Start(string url, string path) { active = client.DownloadFileTaskAsync(new Uri(url), path); return active; }
    public void Dispose() { client.CancelAsync(); if (active != null) { try { active.GetAwaiter().GetResult(); } catch {} } client.Dispose(); }
}
'@
            }
            $client = New-Object CppBoxTransfer
            $task = $client.Start($Url, $partial)
            while (-not $task.IsCompleted) {
                Assert-NotCancelled
                $received = $client.Received
                $total = $client.Total
                $percent = if ($total -gt 0) { [int][math]::Min(99, [math]::Floor($received * 100.0 / $total)) } else { 0 }
                Set-Progress $percent ("download:$Name") $received $total
                Start-Sleep -Milliseconds 150
            }
            $task.GetAwaiter().GetResult()
        }
        Assert-NotCancelled
        if (-not (Test-ZipFile $partial)) { throw "$Name ZIP is broken." }
        Move-Item -LiteralPath $partial -Destination $OutFile -Force
        $size = (Get-Item -LiteralPath $OutFile).Length
        Set-Progress 100 ("download:$Name") $size $size
        Say "[OK] Downloaded $Name"
    } finally {
        if ($bits) { Remove-BitsTransfer -BitsJob $bits -Confirm:$false -ErrorAction SilentlyContinue }
        if ($client) { $client.Dispose() }
        if ([IO.File]::Exists($partial)) { [IO.File]::Delete($partial) }
    }
}

function Expand-Clean {
    param([string]$Zip, [string]$Destination, [string]$Name, [string]$ExpectedFile)
    Assert-NotCancelled
    if ((Test-Path -LiteralPath $Destination) -and (Find-Tool $Destination $ExpectedFile) -and -not (Test-Path -LiteralPath ($Destination + '.extracting'))) {
        Say "[OK] $Name already extracted"; return
    }
    if (-not (Test-ZipFile $Zip)) { throw "$Name ZIP is broken." }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    [IO.File]::WriteAllText(($Destination + '.extracting'), 'incomplete')
    $base = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($entry in $archive.Entries) {
            Assert-NotCancelled
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if (-not $target.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe ZIP entry.' }
            if (-not $entry.Name) { [IO.Directory]::CreateDirectory($target) | Out-Null; continue }
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            $inputStream = $entry.Open()
            $outputStream = $null
            $token = New-Object Threading.CancellationTokenSource
            try {
                $outputStream = [IO.File]::Create($target)
                $copy = $inputStream.CopyToAsync($outputStream, 81920, $token.Token)
                while (-not $copy.IsCompleted) {
                    if ($CancelFile -and [IO.File]::Exists($CancelFile)) { $token.Cancel() }
                    try { [void]$copy.Wait(30) } catch { Assert-NotCancelled; throw }
                }
                try { $copy.GetAwaiter().GetResult() } catch { Assert-NotCancelled; throw }
                Assert-NotCancelled
            } finally {
                if ($outputStream) { $outputStream.Dispose() }
                $inputStream.Dispose()
                $token.Dispose()
            }
        }
        Assert-NotCancelled
        [IO.File]::Delete(($Destination + '.extracting'))
    } finally { $archive.Dispose() }
    Say "[OK] Extracted $Name"
}

function Find-Tool {
    param([string]$RootDir, [string]$FileName)
    $found = Get-ChildItem -LiteralPath $RootDir -Filter $FileName -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Find-CodeExe {
    $direct = Join-Path $VsCode 'Code.exe'
    if (Test-Path -LiteralPath $direct) {
        return $direct
    }
    return Find-Tool $VsCode 'Code.exe'
}

function Write-JsonFile {
    param([string]$Path, [object]$JsonObject)
    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $JsonObject | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Configure-Workspace {
    $gpp = Find-Tool $Toolchain 'g++.exe'
    $gdb = Find-Tool $Toolchain 'gdb.exe'
    if (-not $gpp) { throw 'g++.exe was not found after extraction.' }
    if (-not $gdb) { throw 'gdb.exe was not found after extraction.' }

    $vscodeDir = Join-Path $Workspace '.vscode'
    New-Item -ItemType Directory -Force -Path $vscodeDir, $Build | Out-Null

    $main = Join-Path $Workspace 'hello.cpp'
    if (-not (Test-Path -LiteralPath $main)) {
@'
#include <iostream>

int main() {
    std::cout << "cppbox" << std::endl;
    return 0;
}
'@ | Set-Content -LiteralPath $main -Encoding UTF8
    }

    foreach ($oldFile in @('BUILD_HELLO.bat', 'RUN_HELLO.bat', 'README.txt', 'PUT_CPP_FILES_HERE.txt')) {
        $oldPath = Join-Path $Workspace $oldFile
        if (Test-Path -LiteralPath $oldPath) {
            Remove-Item -LiteralPath $oldPath -Force -ErrorAction SilentlyContinue
        }
    }
    $oldBuildDir = Join-Path $Workspace 'build'
    if (Test-Path -LiteralPath $oldBuildDir) {
        Remove-Item -LiteralPath $oldBuildDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem -LiteralPath $Workspace -Filter '*.exe' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    $settings = @{
        'C_Cpp.default.compilerPath' = $gpp
        'C_Cpp.default.intelliSenseMode' = 'windows-gcc-x64'
        'C_Cpp.default.cppStandard' = 'c++20'
        'terminal.integrated.defaultProfile.windows' = 'Command Prompt'
        'files.autoSave' = 'afterDelay'
        'files.exclude' = @{
            '**/.vscode' = $true
            '**/*.exe' = $true
            '**/build' = $true
        }
    }
    Write-JsonFile (Join-Path $vscodeDir 'settings.json') $settings

    $compilerBin = Split-Path -Parent $gpp

    $tasks = @{
        version = '2.0.0'
        tasks = @(
            @{
                label = 'Build active C++ file'
                type = 'process'
                command = $gpp
                args = @('-std=c++20', '-g', '-O0', '-Wall', '-Wextra', '${file}', '-o', ($Build + '\${fileBasenameNoExtension}.exe'))
                options = @{ cwd = '${workspaceFolder}'; env = @{ PATH = ($compilerBin + ';${env:PATH}') } }
                group = @{ kind = 'build'; isDefault = $true }
                problemMatcher = @('$gcc')
            },
            @{
                label = 'Run active C++ exe'
                type = 'process'
                command = ($Build + '\${fileBasenameNoExtension}.exe')
                options = @{ cwd = '${workspaceFolder}'; env = @{ PATH = ($compilerBin + ';${env:PATH}') } }
                dependsOn = 'Build active C++ file'
                problemMatcher = @()
            }
        )
    }
    Write-JsonFile (Join-Path $vscodeDir 'tasks.json') $tasks

    $launch = @{
        version = '0.2.0'
        configurations = @(
            @{
                name = 'CppBox: Debug active C++ file'
                type = 'cppdbg'
                request = 'launch'
                program = ($Build + '\${fileBasenameNoExtension}.exe')
                args = @()
                stopAtEntry = $false
                cwd = '${workspaceFolder}'
                environment = @(@{ name = 'PATH'; value = ($compilerBin + ';${env:PATH}') })
                externalConsole = $false
                MIMode = 'gdb'
                miDebuggerPath = $gdb
                preLaunchTask = 'Build active C++ file'
                setupCommands = @(@{ text = '-enable-pretty-printing'; ignoreFailures = $true })
            }
        )
    }
    Write-JsonFile (Join-Path $vscodeDir 'launch.json') $launch

    $oldWorkspaceFile = Join-Path $Workspace 'cppbox.code-workspace'
    if (Test-Path -LiteralPath $oldWorkspaceFile) {
        Remove-Item -LiteralPath $oldWorkspaceFile -Force
    }
}

function Install-Extension {
    $code = Find-CodeExe
    if (-not $code) { throw 'Code.exe not found.' }
    Say '[..] Installing Microsoft C/C++ Extension Pack into isolated VS Code data folder'
    $userData = Join-Path $VsCodeData 'user-data'
    $extensions = Join-Path $VsCodeData 'extensions'
    New-Item -ItemType Directory -Force -Path $userData, $extensions | Out-Null
    Assert-NotCancelled
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $code
    $psi.Arguments = '--user-data-dir "' + $userData + '" --extensions-dir "' + $extensions + '" --install-extension ms-vscode.cpptools-extension-pack --force'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['ELECTRON_RUN_AS_NODE'] = '1'
    $codeRoot = Split-Path -Parent $code
    $cli = Join-Path $codeRoot 'resources\app\out\cli.js'
    $codeCmd = Join-Path $codeRoot 'bin\code.cmd'
    if (Test-Path -LiteralPath $codeCmd) {
        $cmdText = [IO.File]::ReadAllText($codeCmd)
        if ($cmdText -match '"%~dp0(?<cli>[^"\r\n]*resources[\\/]app[\\/]out[\\/]cli\.js)"') {
            $cli = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $codeCmd) $Matches['cli']))
        }
    }
    if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) { throw "VS Code CLI not found: $cli" }
    $psi.EnvironmentVariables['VSCODE_DEV'] = ''
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = '"' + $cli + '" ' + $psi.Arguments
    $extensionProcess = [Diagnostics.Process]::Start($psi)
    $stdout = $extensionProcess.StandardOutput.ReadToEndAsync()
    $stderr = $extensionProcess.StandardError.ReadToEndAsync()
    try {
        while (-not $extensionProcess.WaitForExit(150)) { Assert-NotCancelled }
        Assert-NotCancelled
        $outputText = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($outputText) { Say $outputText.Trim() }
        if ($errorText) { Say $errorText.Trim() }
        if ($extensionProcess.ExitCode -ne 0) { throw "Extension installation failed (exit $($extensionProcess.ExitCode))." }
    } finally {
        if (-not $extensionProcess.HasExited) { $extensionProcess.Kill(); $extensionProcess.WaitForExit() }
        $extensionProcess.Dispose()
    }
    Say '[OK] Extension step finished'
}

function Open-VSCode {
    $code = Find-CodeExe
    if (-not $code) { throw 'Code.exe not found.' }
    New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
    $userData = Join-Path $VsCodeData 'user-data'
    $extensions = Join-Path $VsCodeData 'extensions'
    New-Item -ItemType Directory -Force -Path $userData, $extensions | Out-Null
    Start-Process -FilePath $code -ArgumentList @('--new-window', '--user-data-dir', $userData, '--extensions-dir', $extensions, $Workspace)
}

function Stop-CppBoxVSCode {
    $codeRoot = (Resolve-Path -LiteralPath $VsCode -ErrorAction SilentlyContinue)
    if (-not $codeRoot) { return }
    $codeRootText = $codeRoot.Path.ToLowerInvariant()
    Get-Process -Name Code -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $path = $_.Path
            if ($path -and $path.ToLowerInvariant().StartsWith($codeRootText)) {
                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
        }
    }
}

function Stop-CppBoxVSCode-Retry {
    for ($i = 0; $i -lt 8; $i++) {
        Stop-CppBoxVSCode
        Start-Sleep -Milliseconds 350
    }
}

try {
Ensure-Dirs
if (-not $OpenOnly) { [IO.File]::WriteAllText((Join-Path $Internal 'install-incomplete'), 'incomplete') }
Set-Progress 3 'prepare'

if ($OpenOnly) {
    Set-Progress 20 'configure'
    Say 'CppBox Native Portable VS Code launcher'
    Configure-Workspace
    Set-Progress 80 'open'
    Open-VSCode
    Set-Progress 100 'done'
    Say '[OK] VS Code launched.'
    exit 0
}

Say 'CppBox Native Portable VS Code setup'

Set-Progress 8 'prepare-vscode-download'
Download-File $VsCodeUrl $VsCodeZip 'VS Code portable ZIP'
Set-Progress 25 'prepare-compiler-download'
Download-File $WinLibsUrl $WinLibsZip 'WinLibs GCC ZIP'

Set-Progress 40 'verify'
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $WinLibsZip).Hash.ToLowerInvariant()
if ($hash -ne $WinLibsSha256) {
    throw "WinLibs SHA-256 mismatch. Expected $WinLibsSha256, got $hash"
}
Say '[OK] WinLibs SHA-256 verified'

Set-Progress 52 'extract-vscode'
Expand-Clean $VsCodeZip $VsCode 'VS Code' 'Code.exe'
Set-Progress 68 'extract-compiler'
Expand-Clean $WinLibsZip $Toolchain 'WinLibs GCC' 'g++.exe'

Set-Progress 78 'configure'
Configure-Workspace
Set-Progress 88 'extension'
Install-Extension
Stop-CppBoxVSCode-Retry
if (-not $NoOpen) {
    Set-Progress 96 'open'
    Open-VSCode
}

Assert-NotCancelled
[IO.File]::Delete((Join-Path $Internal 'install-incomplete'))
Set-Progress 100 'done'
Say '[OK] Done. Next time launch OPEN_CODE_HERE.bat.'

} catch {
    if ($CancelFile -and [IO.File]::Exists($CancelFile)) {
        Say '[CANCELLED] Installation cancelled; completed downloads retained.'
        exit 1223
    }
    Say ('[ERROR] ' + $_.Exception.Message)
    exit 1
}
