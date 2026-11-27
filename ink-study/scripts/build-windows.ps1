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
    Write-Host 'Installer, Start menu shortcut, app launch, and uninstall checks passed.'
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
