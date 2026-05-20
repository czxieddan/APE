param(
    [string]$Root = (Get-Location).Path,
    [string[]]$ExcludeDirectoryNames = @('localisation'),
    [string[]]$BinaryExtensions = @(
        '.bmp', '.dds', '.gif', '.jpg', '.jpeg', '.ogg', '.png', '.psb',
        '.psd', '.tga', '.tif', '.tiff', '.wav', '.webp'
    ),
    [switch]$DryRun,
    [switch]$VerboseLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$rootPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
$utf8Strict = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
$ansiCodePage = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage
$ansiEncoding = [System.Text.Encoding]::GetEncoding($ansiCodePage)
$excludeLookup = @{}
foreach ($name in ($ExcludeDirectoryNames + '.git')) {
    $excludeLookup[$name.ToLowerInvariant()] = $true
}
$binaryExtensionLookup = @{}
foreach ($extension in $BinaryExtensions) {
    if (-not [string]::IsNullOrWhiteSpace($extension)) {
        $normalizedExtension = $extension.ToLowerInvariant()
        if (-not $normalizedExtension.StartsWith('.')) {
            $normalizedExtension = ".$normalizedExtension"
        }
        $binaryExtensionLookup[$normalizedExtension] = $true
    }
}

function Get-RelativePath {
    param([string]$FullName)

    if ($FullName.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullName.Substring($rootPrefix.Length)
    }

    return $FullName
}

function Test-IsInExcludedDirectory {
    param([string]$FullName)

    $relativePath = Get-RelativePath -FullName $FullName
    $parts = $relativePath -split '[\\/]+'
    if ($parts.Length -le 1) {
        return $false
    }

    for ($i = 0; $i -lt ($parts.Length - 1); $i++) {
        if ($excludeLookup.ContainsKey($parts[$i].ToLowerInvariant())) {
            return $true
        }
    }

    return $false
}

function Test-IsKnownBinaryExtension {
    param([string]$Extension)

    if ([string]::IsNullOrWhiteSpace($Extension)) {
        return $false
    }

    return $binaryExtensionLookup.ContainsKey($Extension.ToLowerInvariant())
}

function Test-LooksBinaryBytes {
    param([byte[]]$Bytes)

    if ($Bytes.Length -eq 0) {
        return $false
    }

    $sampleLength = [Math]::Min($Bytes.Length, 8192)
    $controlCount = 0

    for ($i = 0; $i -lt $sampleLength; $i++) {
        $b = $Bytes[$i]

        if ($b -eq 0) {
            return $true
        }

        if ($b -lt 32 -and $b -ne 9 -and $b -ne 10 -and $b -ne 12 -and $b -ne 13) {
            $controlCount++
        }
    }

    return (($controlCount / [double]$sampleLength) -gt 0.02)
}

function Test-LooksUtf16NoBom {
    param(
        [byte[]]$Bytes,
        [switch]$BigEndian
    )

    if ($Bytes.Length -lt 8) {
        return $false
    }

    $sampleLength = [Math]::Min($Bytes.Length, 8192)
    $evenZeros = 0
    $oddZeros = 0
    $pairs = [Math]::Floor($sampleLength / 2)

    for ($i = 0; $i -lt ($pairs * 2); $i += 2) {
        if ($Bytes[$i] -eq 0) {
            $evenZeros++
        }
        if ($Bytes[$i + 1] -eq 0) {
            $oddZeros++
        }
    }

    if ($pairs -eq 0) {
        return $false
    }

    if ($BigEndian) {
        return (($evenZeros / [double]$pairs) -gt 0.30 -and ($oddZeros / [double]$pairs) -lt 0.05)
    }

    return (($oddZeros / [double]$pairs) -gt 0.30 -and ($evenZeros / [double]$pairs) -lt 0.05)
}

function Get-DecodedText {
    param([byte[]]$Bytes)

    if ($Bytes.Length -eq 0) {
        return @{
            IsText = $true
            Text = ''
            SourceEncoding = 'empty'
        }
    }

    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE -and $Bytes[2] -eq 0x00 -and $Bytes[3] -eq 0x00) {
        return @{
            IsText = $true
            Text = ([System.Text.Encoding]::UTF32.GetString($Bytes, 4, $Bytes.Length - 4))
            SourceEncoding = 'utf-32-le-bom'
        }
    }

    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0x00 -and $Bytes[1] -eq 0x00 -and $Bytes[2] -eq 0xFE -and $Bytes[3] -eq 0xFF) {
        return @{
            IsText = $true
            Text = ((New-Object System.Text.UTF32Encoding -ArgumentList $true, $true).GetString($Bytes, 4, $Bytes.Length - 4))
            SourceEncoding = 'utf-32-be-bom'
        }
    }

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return @{
            IsText = $true
            Text = $utf8Strict.GetString($Bytes, 3, $Bytes.Length - 3)
            SourceEncoding = 'utf-8-bom'
        }
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return @{
            IsText = $true
            Text = ([System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2))
            SourceEncoding = 'utf-16-le-bom'
        }
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return @{
            IsText = $true
            Text = ([System.Text.Encoding]::BigEndianUnicode.GetString($Bytes, 2, $Bytes.Length - 2))
            SourceEncoding = 'utf-16-be-bom'
        }
    }

    if (Test-LooksUtf16NoBom -Bytes $Bytes) {
        return @{
            IsText = $true
            Text = ([System.Text.Encoding]::Unicode.GetString($Bytes))
            SourceEncoding = 'utf-16-le'
        }
    }

    if (Test-LooksUtf16NoBom -Bytes $Bytes -BigEndian) {
        return @{
            IsText = $true
            Text = ([System.Text.Encoding]::BigEndianUnicode.GetString($Bytes))
            SourceEncoding = 'utf-16-be'
        }
    }

    if (Test-LooksBinaryBytes -Bytes $Bytes) {
        return @{
            IsText = $false
            Text = $null
            SourceEncoding = 'binary'
        }
    }

    try {
        return @{
            IsText = $true
            Text = $utf8Strict.GetString($Bytes)
            SourceEncoding = 'utf-8'
        }
    }
    catch [System.Text.DecoderFallbackException] {
        return @{
            IsText = $true
            Text = $ansiEncoding.GetString($Bytes)
            SourceEncoding = "ansi-$ansiCodePage"
        }
    }
}

function Test-ByteArraysEqual {
    param(
        [byte[]]$Left,
        [byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }

    for ($i = 0; $i -lt $Left.Length; $i++) {
        if ($Left[$i] -ne $Right[$i]) {
            return $false
        }
    }

    return $true
}

$stats = [ordered]@{
    Root = $rootFull
    DryRun = [bool]$DryRun
    Scanned = 0
    Excluded = 0
    BinarySkipped = 0
    Unchanged = 0
    Converted = 0
    Errors = 0
}

$sourceEncodingCounts = @{}
$files = Get-ChildItem -LiteralPath $rootFull -Recurse -File

foreach ($file in $files) {
    if (Test-IsInExcludedDirectory -FullName $file.FullName) {
        $stats.Excluded++
        continue
    }

    $stats.Scanned++
    $relativePath = Get-RelativePath -FullName $file.FullName

    try {
        if (Test-IsKnownBinaryExtension -Extension $file.Extension) {
            $stats.BinarySkipped++
            if ($VerboseLog) {
                Write-Host "skip binary extension: $relativePath"
            }
            continue
        }

        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $decoded = Get-DecodedText -Bytes $bytes

        if (-not $decoded.IsText) {
            $stats.BinarySkipped++
            if ($VerboseLog) {
                Write-Host "skip binary: $relativePath"
            }
            continue
        }

        $source = [string]$decoded.SourceEncoding
        if (-not $sourceEncodingCounts.ContainsKey($source)) {
            $sourceEncodingCounts[$source] = 0
        }
        $sourceEncodingCounts[$source]++

        $targetBytes = $utf8NoBom.GetBytes([string]$decoded.Text)
        if (Test-ByteArraysEqual -Left $bytes -Right $targetBytes) {
            $stats.Unchanged++
            continue
        }

        $stats.Converted++
        if ($DryRun) {
            Write-Host "would convert [$source]: $relativePath"
        }
        else {
            [System.IO.File]::WriteAllBytes($file.FullName, $targetBytes)
            Write-Host "converted [$source]: $relativePath"
        }
    }
    catch {
        $stats.Errors++
        Write-Warning "failed: $relativePath :: $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host 'Summary'
foreach ($key in $stats.Keys) {
    Write-Host ("{0}: {1}" -f $key, $stats[$key])
}

Write-Host ''
Write-Host 'Detected text source encodings'
foreach ($key in ($sourceEncodingCounts.Keys | Sort-Object)) {
    Write-Host ("{0}: {1}" -f $key, $sourceEncodingCounts[$key])
}

if ($stats.Errors -gt 0) {
    exit 1
}
