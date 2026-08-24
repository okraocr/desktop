param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [Parameter(Mandatory=$true)][string]$StatusPath
)

# okraPDF Chandra OCR 2 managed setup for Windows.
# Mirrors apps/desktop/OkraPDF/ProviderScripts/install-chandra-ocr.sh on macOS:
# creates a pinned venv, downloads pinned model artifacts with SHA-256
# verification, and writes the .ready marker that matches the runtime lock.
# Retries resume: already-verified artifacts in model.partial are kept.

$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-Status {
    param([string]$Phase, [string]$Message)
    $json = [pscustomobject]@{
        phase     = $Phase
        message   = $Message
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($StatusPath, $json, $script:Utf8NoBom)
    Write-Output "[$Phase] $Message"
}

function Find-Python {
    $candidates = @(
        @('py', '-3'),
        @('python'),
        @('python3')
    )
    foreach ($candidate in $candidates) {
        $exe = $candidate[0]
        $prefix = @($candidate | Select-Object -Skip 1)
        try {
            $versionOutput = & $exe @prefix --version 2>$null
        } catch {
            continue
        }
        if ($LASTEXITCODE -ne 0 -or -not $versionOutput) { continue }
        $version = ($versionOutput -replace '^Python\s+', '').Trim()
        $parts = $version.Split('.')
        if ($parts.Count -ge 2 -and [int]$parts[0] -eq 3 -and [int]$parts[1] -ge 10) {
            return ,@($exe, $prefix)
        }
    }
    throw 'Python 3.10 or later is required for Chandra OCR 2 setup. Install it from python.org and retry.'
}

function Test-Artifact {
    param([string]$Path, [int64]$ExpectedSize, [string]$ExpectedSha256)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $size = (Get-Item -LiteralPath $Path).Length
    if ($size -ne $ExpectedSize) { return $false }
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
    return $hash -eq $ExpectedSha256
}

try {
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $venvDir = Join-Path $Root 'venv'
    $venvPython = Join-Path $venvDir 'Scripts\python.exe'
    $modelDir = Join-Path $Root 'model'
    $stagingDir = Join-Path $Root 'model.partial'
    $readyPath = Join-Path $Root '.ready'

    if (-not (Test-Path -LiteralPath $venvPython)) {
        Write-Status 'venv' 'Locating Python 3.10+...'
        $pythonParts = Find-Python
        $pythonExe = $pythonParts[0]
        $pythonPrefix = @($pythonParts | Select-Object -Skip 1)
        Write-Status 'venv' "Creating the managed runtime in $venvDir..."
        & $pythonExe @pythonPrefix -m venv $venvDir
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the Chandra OCR 2 virtual environment.' }
    } else {
        Write-Status 'venv' 'Managed runtime already exists; reusing it.'
    }

    # Track selection (Ollama-style host adaptation): CUDA-capable NVIDIA GPU
    # gets fast 8-bit-quantized inference; everything else gets the CPU build.
    $hasCuda = $false
    try {
        & nvidia-smi --query-gpu=name --format=csv 2>$null | Out-Null
        $hasCuda = ($LASTEXITCODE -eq 0)
    } catch {
        $hasCuda = $false
    }
    if ($hasCuda) {
        $runtimeLock = $manifest.runtimeLockCuda
        Write-Status 'runtime' 'NVIDIA GPU detected; installing pinned torch (CUDA 12.6)...'
        & $venvPython -m pip install --no-input --disable-pip-version-check 'torch==2.13.0+cu126' 'torchvision==0.28.0+cu126' --index-url https://download.pytorch.org/whl/cu126
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the pinned CUDA torch runtime.' }
        & $venvPython -m pip install --no-input --disable-pip-version-check 'bitsandbytes>=0.50' 'accelerate>=1.14'
        if ($LASTEXITCODE -ne 0) { throw 'Could not install bitsandbytes for 8-bit GPU quantization.' }
    } else {
        $runtimeLock = $manifest.runtimeLockCpu
        Write-Status 'runtime' 'No NVIDIA GPU detected; installing pinned torch (CPU)...'
        & $venvPython -m pip install --no-input --disable-pip-version-check 'torch==2.13.0+cpu' 'torchvision==0.28.0+cpu' --index-url https://download.pytorch.org/whl/cpu
        if ($LASTEXITCODE -ne 0) { throw 'Could not install the pinned torch runtime.' }
    }
    & $venvPython -m pip install --no-input --disable-pip-version-check --upgrade pip | Out-Null

    Write-Status 'runtime' 'Installing pinned transformers...'
    & $venvPython -m pip install --no-input --disable-pip-version-check 'transformers==5.15.0' 'huggingface-hub==1.24.0' 'pillow>=11'
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the pinned transformers runtime.' }

    # Fast path: a previous install already produced a verified model
    # directory — skip the download phase entirely (Ollama-style retries).
    $alreadyVerified = $true
    foreach ($artifact in $manifest.artifacts) {
        if (-not (Test-Artifact -Path (Join-Path $modelDir $artifact.path) -ExpectedSize ([int64]$artifact.size) -ExpectedSha256 $artifact.sha256)) {
            $alreadyVerified = $false
            break
        }
    }
    if ($alreadyVerified) {
        Write-Status 'verify' 'Managed model already downloaded and verified; skipping download.'
    } else {
    Write-Status 'model' 'Downloading pinned Chandra OCR 2 artifacts (~10.6 GB)...'
    New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null

    # Ollama-style managed download: one content-addressed blob store (HF
    # cache layout under <root>/huggingface), resume-on-retry, real progress,
    # and a junction into the snapshot so nothing is duplicated.
    $hfHome = Join-Path $Root 'huggingface'
    New-Item -ItemType Directory -Force -Path $hfHome | Out-Null
    $blobsDir = Join-Path $hfHome 'hub\models--datalab-to--chandra-ocr-2\blobs'
    $expectedTotal = 0
    foreach ($artifact in $manifest.artifacts) { $expectedTotal += [int64]$artifact.size }

    $allowPatterns = ($manifest.artifacts | ForEach-Object { "'$($_.path)'" }) -join ', '
    $downloadWorker = Join-Path $Root 'snapshot-download.py'
    [System.IO.File]::WriteAllText($downloadWorker, "from huggingface_hub import snapshot_download`nprint(snapshot_download(repo_id='$($manifest.repository)', revision='$($manifest.revision)', allow_patterns=[$allowPatterns]))`n", $script:Utf8NoBom)
    $downloadOut = Join-Path $Root 'model-download.out'
    $downloadErr = Join-Path $Root 'model-download.err'
    $env:HF_HOME = $hfHome
    $downloadProc = Start-Process -FilePath $venvPython -ArgumentList $downloadWorker -NoNewWindow -PassThru -RedirectStandardOutput $downloadOut -RedirectStandardError $downloadErr

    while (-not $downloadProc.HasExited) {
        Start-Sleep -Seconds 5
        $present = 0
        if (Test-Path -LiteralPath $blobsDir) {
            Get-ChildItem -LiteralPath $blobsDir -Recurse -File -ErrorAction SilentlyContinue |
                ForEach-Object { $present += $_.Length }
        }
        $percent = [math]::Floor(($present / [math]::Max($expectedTotal, 1)) * 100)
        $presentGB = [math]::Round($present / 1GB, 1)
        $totalGB = [math]::Round($expectedTotal / 1GB, 1)
        Write-Status 'model' "Downloading Chandra OCR 2... $presentGB / $totalGB GB ($percent%). Retry-resume is safe."
        $downloadProc.Refresh()
    }
    $downloadProc.WaitForExit()
    # Start-Process with redirects does not reliably surface ExitCode on
    # Windows PowerShell 5.1; success is defined by the snapshot the
    # downloader printed, not by the exit code.
    $snapshotPath = (Get-Content -LiteralPath $downloadOut -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1).Trim()
    if ([string]::IsNullOrWhiteSpace($snapshotPath) -or -not (Test-Path -LiteralPath $snapshotPath)) {
        $detail = Get-Content -LiteralPath $downloadErr -Tail 5 -ErrorAction SilentlyContinue
        throw "Model download failed: $detail. Run setup again; downloaded blobs resume automatically."
    }

    Write-Status 'verify' 'Verifying pinned artifact hashes (SHA-256)...'
    foreach ($artifact in $manifest.artifacts) {
        $snapshotFile = Join-Path $snapshotPath $artifact.path
        if (-not (Test-Path -LiteralPath $snapshotFile)) {
            throw "Missing downloaded artifact: $($artifact.path)"
        }
        $size = (Get-Item -LiteralPath $snapshotFile).Length
        if ($size -ne [int64]$artifact.size) {
            throw "$($artifact.path) has size $size, expected $($artifact.size). Run setup again; blobs resume automatically."
        }
        $hash = (Get-FileHash -LiteralPath $snapshotFile -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $artifact.sha256) {
            Remove-Item -LiteralPath $snapshotFile -Force -ErrorAction SilentlyContinue
            throw "$($artifact.path) did not match the pinned Chandra OCR 2 model. It was removed; run setup again to download it."
        }
    }

    Write-Status 'verify' 'Finalizing the managed model...'
    if (Test-Path -LiteralPath $modelDir) {
        Remove-Item -LiteralPath $modelDir -Recurse -Force
    }
    # Junction into the content-addressed snapshot: one copy of the weights.
    New-Item -ItemType Junction -Path $modelDir -Target $snapshotPath | Out-Null
    if (Test-Path -LiteralPath $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    }

    $marker = [pscustomobject]@{
        schemaVersion      = 1
        modelRevision      = $manifest.revision
        runtimeLockVersion = $runtimeLock
        installedAt        = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($readyPath, $marker, $script:Utf8NoBom)

    Write-Status 'done' 'Chandra OCR 2 is ready offline.'
    exit 0
} catch {
    Write-Status 'error' $_.Exception.Message
    exit 1
}
