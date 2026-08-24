param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$StatusPath
)

# Managed Microsoft Presidio setup for okraPDF Windows. The runtime and spaCy
# model live under ~/.okra/providers/presidio and are reused across app runs.
$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$presidioVersion = '2.2.364'
$spacyModelVersion = '3.8.0'
$spacyModelUrl = "https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-$spacyModelVersion/en_core_web_sm-$spacyModelVersion-py3-none-any.whl"

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
    throw 'Python 3.10 or later is required for Presidio setup. Install it from python.org and retry.'
}

try {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $venvDir = Join-Path $Root 'venv'
    $venvPython = Join-Path $venvDir 'Scripts\python.exe'
    $readyPath = Join-Path $Root '.ready'

    if (-not (Test-Path -LiteralPath $venvPython)) {
        Write-Status 'venv' 'Locating Python 3.10+...'
        $pythonParts = Find-Python
        $pythonExe = $pythonParts[0]
        $pythonPrefix = @($pythonParts | Select-Object -Skip 1)
        Write-Status 'venv' "Creating the managed Presidio runtime in $venvDir..."
        & $pythonExe @pythonPrefix -m venv $venvDir
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the Presidio virtual environment.' }
    } else {
        Write-Status 'venv' 'Managed Presidio runtime already exists; reusing it.'
    }

    Write-Status 'runtime' "Installing Microsoft Presidio $presidioVersion with local Ollama support..."
    & $venvPython -m pip install --no-input --disable-pip-version-check --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw 'Could not upgrade pip in the Presidio runtime.' }
    & $venvPython -m pip install --no-input --disable-pip-version-check "presidio-analyzer[langextract]==$presidioVersion" $spacyModelUrl
    if ($LASTEXITCODE -ne 0) { throw 'Could not install Presidio and the English spaCy model.' }

    Write-Status 'verify' 'Verifying the local Presidio analyzer and spaCy model...'
    & $venvPython -c "import presidio_analyzer, spacy; spacy.load('en_core_web_sm'); from presidio_analyzer.predefined_recognizers.third_party.basic_langextract_recognizer import BasicLangExtractRecognizer; print('ok')"
    if ($LASTEXITCODE -ne 0) { throw 'Presidio verification failed.' }

    $marker = [pscustomobject]@{
        schemaVersion      = 1
        presidioVersion   = $presidioVersion
        spacyModelVersion = $spacyModelVersion
        installedAt       = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText($readyPath, $marker, $script:Utf8NoBom)
    Write-Status 'done' 'Microsoft Presidio is ready locally.'
    exit 0
} catch {
    Write-Status 'error' $_.Exception.Message
    exit 1
}
