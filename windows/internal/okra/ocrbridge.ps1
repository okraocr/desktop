param(
    [string]$Path,
    [switch]$Check
)

# okraPDF Windows OCR bridge.
# Uses the built-in Windows.Media.Ocr WinRT engine (the Windows equivalent of
# Apple Vision on macOS). Prints exactly one compact JSON object to stdout;
# errors go to stderr with a non-zero exit code.

$ErrorActionPreference = 'Stop'

# Force UTF-8 stdout. In a no-console child process the output encoding falls
# back to the OEM codepage (CP437), which would silently rewrite Unicode OCR
# text (e.g. a bullet U+2022 becomes byte 0x07) and corrupt the JSON payload.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

    [void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
    [void][Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType=WindowsRuntime]
    [void][Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
    [void][Windows.Storage.FileAccessMode, Windows.Storage, ContentType=WindowsRuntime]
    [void][Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.BitmapPixelFormat, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.BitmapAlphaMode, Windows.Graphics.Imaging, ContentType=WindowsRuntime]

    $script:asTaskMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
        } |
        Select-Object -First 1

    if ($null -eq $script:asTaskMethod) {
        throw 'Could not locate the WinRT AsTask bridge method.'
    }

    function Wait-WinRTOperation {
        param([object]$Operation, [type]$ResultType)
        $generic = $script:asTaskMethod.MakeGenericMethod($ResultType)
        $task = $generic.Invoke($null, @($Operation))
        try {
            $task.Wait()
        } catch [System.AggregateException] {
            throw $_.Exception.InnerException
        }
        return $task.Result
    }

    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -eq $engine) {
        $languages = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages
        if ($null -eq $languages -or $languages.Count -eq 0) {
            throw 'No Windows OCR language packs are installed. Install a display language to enable OCR.'
        }
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($languages[0])
    }
    if ($null -eq $engine) {
        throw 'Could not create a Windows OCR engine.'
    }

    if ($Check) {
        [pscustomobject]@{
            available         = $true
            language          = $engine.RecognizerLanguage.LanguageTag
            maxImageDimension = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
        } | ConvertTo-Json -Compress
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'No image path was provided.'
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Image not found: $Path"
    }
    $fullPath = (Resolve-Path -LiteralPath $Path).Path

    $file = Wait-WinRTOperation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($fullPath)) ([Windows.Storage.StorageFile])
    $stream = Wait-WinRTOperation ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    try {
        $decoder = Wait-WinRTOperation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Wait-WinRTOperation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        if ($bitmap.BitmapPixelFormat -ne [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8 -or
            $bitmap.BitmapAlphaMode -ne [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied) {
            $bitmap = [Windows.Graphics.Imaging.SoftwareBitmap]::Convert(
                $bitmap,
                [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,
                [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied
            )
        }

        $maxDimension = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
        if ($bitmap.PixelWidth -gt $maxDimension -or $bitmap.PixelHeight -gt $maxDimension) {
            throw "Image $($bitmap.PixelWidth)x$($bitmap.PixelHeight) exceeds the Windows OCR limit of $maxDimension px."
        }

        $result = Wait-WinRTOperation ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

        $lines = [System.Collections.Generic.List[object]]::new()
        foreach ($line in $result.Lines) {
            $minX = [double]::MaxValue
            $minY = [double]::MaxValue
            $maxX = 0.0
            $maxY = 0.0
            foreach ($word in $line.Words) {
                $rect = $word.BoundingRect
                if ($rect.X -lt $minX) { $minX = $rect.X }
                if ($rect.Y -lt $minY) { $minY = $rect.Y }
                if (($rect.X + $rect.Width) -gt $maxX) { $maxX = $rect.X + $rect.Width }
                if (($rect.Y + $rect.Height) -gt $maxY) { $maxY = $rect.Y + $rect.Height }
            }
            if ($minX -eq [double]::MaxValue) { continue }
            # Strip C0 control characters: Windows PowerShell's ConvertTo-Json
            # does not escape them, which would produce invalid JSON.
            $cleanText = ($line.Text -replace '[\x00-\x1F]', ' ').Trim()
            if ([string]::IsNullOrWhiteSpace($cleanText)) { continue }
            $lines.Add([pscustomobject]@{
                text   = $cleanText
                x      = [math]::Round($minX, 2)
                y      = [math]::Round($minY, 2)
                width  = [math]::Round($maxX - $minX, 2)
                height = [math]::Round($maxY - $minY, 2)
            })
        }

        [pscustomobject]@{
            available   = $true
            language    = $engine.RecognizerLanguage.LanguageTag
            imageWidth  = $bitmap.PixelWidth
            imageHeight = $bitmap.PixelHeight
            lines       = $lines
        } | ConvertTo-Json -Compress -Depth 4
        exit 0
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
} catch {
    $message = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = [string]$_
    }
    [Console]::Error.WriteLine($message)
    exit 1
}
