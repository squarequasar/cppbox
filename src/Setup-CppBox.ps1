param(
    [switch]$OpenOnly,
    [switch]$NoOpen,
    [string]$ProgressFile = ''
)

# CppBox setup engine
# made by squarequasar
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression

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
    param([int]$Percent, [string]$Stage)
    if ($ProgressFile) {
        $parent = Split-Path -Parent $ProgressFile
        if ($parent) {
            New-Item -ItemType Directory -Force -Path $parent | Out-Null
        }
        ('{0}|{1}' -f $Percent, $Stage) | Set-Content -LiteralPath $ProgressFile -Encoding ASCII
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

function Download-File {
    param([string]$Url, [string]$OutFile, [string]$Name)
    if (Test-ZipFile $OutFile) {
        Say "[OK] Cached $Name"
        return
    }

    if (Test-Path -LiteralPath $OutFile) {
        Say "[..] Removing broken cached $Name"
        Remove-Item -LiteralPath $OutFile -Force
    }

    $ProgressPreference = 'SilentlyContinue'

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Say "[..] Downloading $Name (attempt $attempt/3)"
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        if (Test-ZipFile $OutFile) {
            Say "[OK] Downloaded $Name"
            return
        }
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
    }

    throw "$Name download failed: downloaded ZIP is broken."
}

function Expand-Clean {
    param(
        [string]$Zip,
        [string]$Destination,
        [string]$Name,
        [string]$ExpectedFile
    )
    if (Test-Path -LiteralPath $Destination) {
        $expected = Find-Tool $Destination $ExpectedFile
        if ($expected) {
            Say "[OK] $Name already extracted"
            return
        }
    }
    if (-not (Test-ZipFile $Zip)) {
        if (Test-Path -LiteralPath $Zip) {
            Remove-Item -LiteralPath $Zip -Force
        }
        throw "$Name ZIP is broken. Run INSTALL_ONCE.bat again to download it fresh."
    }

    Say "[..] Extracting $Name"
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $Destination -Force
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

    $buildCommand = 'if not exist "' + $Build + '" mkdir "' + $Build + '" && "' + $gpp + '" -std=c++20 -Wall -Wextra "${file}" -o "' + $Build + '\${fileBasenameNoExtension}.exe"'
    $runCommand = '"' + $Build + '\${fileBasenameNoExtension}.exe"'

    $tasks = @{
        version = '2.0.0'
        tasks = @(
            @{
                label = 'Build active C++ file'
                type = 'shell'
                command = 'cmd'
                args = @('/d', '/c', $buildCommand)
                group = @{ kind = 'build'; isDefault = $true }
                problemMatcher = @('$gcc')
            },
            @{
                label = 'Run active C++ exe'
                type = 'shell'
                command = 'cmd'
                args = @('/d', '/c', $runCommand)
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
                name = 'Debug active C++ file'
                type = 'cppdbg'
                request = 'launch'
                program = ($Build + '\${fileBasenameNoExtension}.exe')
                args = @()
                stopAtEntry = $false
                cwd = '${workspaceFolder}'
                environment = @()
                externalConsole = $false
                MIMode = 'gdb'
                miDebuggerPath = $gdb
                preLaunchTask = 'Build active C++ file'
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
    & $code --user-data-dir $userData --extensions-dir $extensions --install-extension ms-vscode.cpptools-extension-pack --force
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

Ensure-Dirs
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

Set-Progress 8 'download-vscode'
Download-File $VsCodeUrl $VsCodeZip 'VS Code portable ZIP'
Set-Progress 25 'download-compiler'
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

Set-Progress 100 'done'
Say '[OK] Done. Next time launch OPEN_CODE_HERE.bat.'
