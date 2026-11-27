[CmdletBinding()]
param(
    [string]$InnoCompiler,
    [switch]$VerifyInstall
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot

function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

function Initialize-WindowsRunner {
    $runner = Join-Path $projectDir 'windows'
    if (-not (Test-Path -LiteralPath (Join-Path $runner 'CMakeLists.txt'))) {
        $template = Join-Path ([IO.Path]::GetTempPath()) ("ink-study-runner-" + [guid]::NewGuid().ToString('N'))
        try {
            Invoke-Checked 'flutter' @('create', '--platforms=windows', '--project-name=ink_study', '--no-pub', $template)
            Copy-Item -LiteralPath (Join-Path $template 'windows') -Destination $projectDir -Recurse
        }
        finally {
            if (Test-Path -LiteralPath $template) {
                Remove-Item -LiteralPath $template -Recurse -Force
            }
        }
    }

    $main = Join-Path $runner 'runner/main.cpp'
    $resources = Join-Path $runner 'runner/Runner.rc'
    [IO.File]::WriteAllText($main, [IO.File]::ReadAllText($main).Replace('L"ink_study"', 'L"Ink Study"'))
    $metadata = [IO.File]::ReadAllText($resources) -replace '(?m)(VALUE "(?:FileDescription|ProductName)", )"ink_study', '$1"Ink Study'
    [IO.File]::WriteAllText($resources, $metadata)

    $icon = Join-Path $projectDir 'installer/InkStudy.ico'
    if (Test-Path -LiteralPath $icon) {
        Copy-Item -LiteralPath $icon -Destination (Join-Path $runner 'runner/resources/app_icon.ico') -Force
    }
}

function Find-InnoCompiler {
    if ($InnoCompiler) {
        return (Get-Item -LiteralPath $InnoCompiler).FullName
    }
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        foreach ($version in @('Inno Setup 7', 'Inno Setup 6')) {
            $path = Join-Path $base "$version/ISCC.exe"
            if (Test-Path -LiteralPath $path) {
                return $path
            }
        }
    }
    throw 'Inno Setup was not found. Pass its ISCC.exe path as -InnoCompiler.'
}

function Copy-VisualCppRuntime([string]$ReleaseDir) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw 'Visual Studio Installer could not be found.'
    }
    $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $visualStudio) {
        throw 'Visual Studio with Desktop development with C++ is required.'
    }

    $redist = Join-Path $visualStudio 'VC/Redist/MSVC'
    $crt = Get-ChildItem -Path "$redist/*/x64/Microsoft.VC*.CRT" -Directory |
        Sort-Object { [version]$_.Parent.Parent.Name } -Descending |
        Select-Object -First 1
    if (-not $crt) {
        throw "The x64 Visual C++ redistributable files were not found in $redist."
    }
    Get-ChildItem -LiteralPath $crt.FullName -File -Filter '*.dll' |
        Copy-Item -Destination $ReleaseDir -Force
    foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $ReleaseDir $dll))) {
            throw "$dll is missing from the app-local Visual C++ runtime."
        }
    }
}

function Wait-AppWindow([scriptblock]$Condition, [string]$Failure) {
    $timeout = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 100
    } while ($timeout.Elapsed.TotalSeconds -lt 12)
    throw $Failure
}

function Test-AppWindow([Diagnostics.Process]$Process) {
    if (-not ('InkStudyWindowTest' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class InkStudyWindowTest {
    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr window);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);

    public static IntPtr FlutterView(IntPtr window) {
        const uint GW_CHILD = 5;
        return GetWindow(window, GW_CHILD);
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowLong(IntPtr window, int index);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint MapVirtualKey(uint code, uint mapType);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    public static bool HasResizeFrame(IntPtr window) {
        const int GWL_STYLE = -16;
        const int WS_THICKFRAME = 0x00040000;
        return (GetWindowLong(window, GWL_STYLE) & WS_THICKFRAME) != 0;
    }

    public static bool SystemCommand(IntPtr window, int command) {
        const uint WM_SYSCOMMAND = 0x0112;
        return PostMessage(window, WM_SYSCOMMAND, new IntPtr(command), IntPtr.Zero);
    }

    public static bool PressKey(IntPtr view, int key) {
        const uint WM_KEYDOWN = 0x0100;
        const uint WM_KEYUP = 0x0101;
        uint scan = MapVirtualKey((uint)key, 0);
        int down = (int)((scan << 16) | 1);
        int up = down | unchecked((int)0xc0000000);
        return PostMessage(view, WM_KEYDOWN, new IntPtr(key), new IntPtr(down)) &&
               PostMessage(view, WM_KEYUP, new IntPtr(key), new IntPtr(up));
    }
}
'@
    }

    Wait-AppWindow {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "The installed app stopped during launch (exit $($Process.ExitCode))."
        }
        $Process.MainWindowHandle -ne [IntPtr]::Zero
    } 'The installed app did not display a main window.'
    $window = $Process.MainWindowHandle
    Wait-AppWindow { [InkStudyWindowTest]::IsZoomed($window) } 'Ink Study did not open maximized.'

    # Exercise the installed runner through native window messages. Restoring
    # first lets the fullscreen check observe a change from an ordinary window.
    $restore = 0xF120
    $minimize = 0xF020
    $maximize = 0xF030
    $normal = { -not [InkStudyWindowTest]::IsZoomed($window) -and -not [InkStudyWindowTest]::IsIconic($window) }
    if (-not [InkStudyWindowTest]::SystemCommand($window, $restore)) { throw 'Could not request restore.' }
    Wait-AppWindow $normal 'Ink Study did not restore from maximized.'
    if (-not [InkStudyWindowTest]::SystemCommand($window, $maximize)) { throw 'Could not request maximize.' }
    Wait-AppWindow { [InkStudyWindowTest]::IsZoomed($window) } 'Ink Study did not maximize.'
    if (-not [InkStudyWindowTest]::SystemCommand($window, $restore)) { throw 'Could not request restore.' }
    Wait-AppWindow $normal 'Ink Study did not restore before minimizing.'
    if (-not [InkStudyWindowTest]::SystemCommand($window, $minimize)) { throw 'Could not request minimize.' }
    Wait-AppWindow { [InkStudyWindowTest]::IsIconic($window) } 'Ink Study did not minimize.'
    if (-not [InkStudyWindowTest]::SystemCommand($window, $restore)) { throw 'Could not request restore.' }
    Wait-AppWindow $normal 'Ink Study did not restore from minimized.'

    $view = [InkStudyWindowTest]::FlutterView($window)
    if ($view -eq [IntPtr]::Zero) { throw 'Ink Study did not create a Flutter view.' }
    if (-not [InkStudyWindowTest]::HasResizeFrame($window)) { throw 'Ink Study did not have a resizable window before fullscreen.' }
    if (-not [InkStudyWindowTest]::PressKey($view, 0x7A)) { throw 'Could not send F11 to Ink Study.' }
    Wait-AppWindow { -not [InkStudyWindowTest]::HasResizeFrame($window) } 'F11 did not enter fullscreen.'
    if (-not [InkStudyWindowTest]::PressKey($view, 0x1B)) { throw 'Could not send Escape to Ink Study.' }
    Wait-AppWindow { [InkStudyWindowTest]::HasResizeFrame($window) } 'Escape did not exit fullscreen.'
}

function Test-Installer([string]$Installer) {
    $installDir = Join-Path ([IO.Path]::GetTempPath()) ("ink-study-install-" + [guid]::NewGuid().ToString('N'))
    $process = $null
    try {
        $setup = Start-Process -FilePath $Installer -ArgumentList @('/SP-', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=`"$installDir`"") -Wait -PassThru
        if ($setup.ExitCode -ne 0) {
            throw "Ink Study Setup failed to install (exit $($setup.ExitCode))."
        }
        $app = Join-Path $installDir 'ink_study.exe'
        $shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Ink Study.lnk'
        if (-not (Test-Path -LiteralPath $shortcut)) {
            throw 'Ink Study does not appear in Start after installation.'
        }
        $process = Start-Process -FilePath $app -WorkingDirectory $installDir -PassThru
        Start-Sleep -Seconds 6
        $process.Refresh()
        if ($process.HasExited) {
            throw "The installed app stopped during launch (exit $($process.ExitCode))."
        }
        Test-AppWindow $process
    }
    finally {
        if ($process -and -not $process.HasExited) {
            if (-not $process.CloseMainWindow() -or -not $process.WaitForExit(4000)) {
                Stop-Process -Id $process.Id
                $process.WaitForExit()
            }
        }
        $uninstall = Join-Path $installDir 'unins000.exe'
        if (Test-Path -LiteralPath $uninstall) {
            $removed = Start-Process -FilePath $uninstall -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -Wait -PassThru
            if ($removed.ExitCode -ne 0 -or (Test-Path -LiteralPath (Join-Path $installDir 'ink_study.exe'))) {
                throw "Ink Study failed to uninstall (exit $($removed.ExitCode))."
            }
        }
    }
    Write-Host 'Installer, Start menu shortcut, app launch, native window state, F11/Escape, and uninstall checks passed.'
}

Push-Location $projectDir
try {
    Initialize-WindowsRunner
    # Doctor also reports unrelated development targets. The Windows build
    # below determines whether the required Windows toolchain is available.
    & flutter doctor -v
    Invoke-Checked 'flutter' @('pub', 'get')
    Invoke-Checked 'flutter' @('analyze', '--no-pub')
    Invoke-Checked 'flutter' @('test', '--no-pub')
    Invoke-Checked 'flutter' @('build', 'windows', '--release', '--no-pub')

    $releaseDir = Join-Path $projectDir 'build/windows/x64/runner/Release'
    if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'ink_study.exe'))) {
        throw "The compiled Windows executable is missing from $releaseDir."
    }
    Copy-VisualCppRuntime $releaseDir

    $pubspec = Get-Content -LiteralPath 'pubspec.yaml' -Raw
    if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)') {
        throw 'pubspec.yaml must declare an application version.'
    }
    $version = $Matches[1]
    $dist = Join-Path $projectDir 'dist'
    $installer = Join-Path $dist 'InkStudy-Setup.exe'
    if (Test-Path -LiteralPath $installer) {
        Remove-Item -LiteralPath $installer -Force
    }
    $script = Join-Path $projectDir 'installer/InkStudy.iss'
    Invoke-Checked (Find-InnoCompiler) @("/DReleaseDir=$releaseDir", "/DAppVersion=$version", "/O$dist", $script)
    if (-not (Test-Path -LiteralPath $installer)) {
        throw "The installer was not created at $installer."
    }
    if ($VerifyInstall) {
        Test-Installer $installer
    }
    Write-Host "Installer: $installer"
}
finally {
    Pop-Location
}
