param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetFullPath($RepoRoot)
$zipPath = Join-Path $repo 'downloads\ch12\ch12-practice.zip'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("verify-ch12-" + [guid]::NewGuid().ToString('N'))

if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "ZIP file not found: $zipPath"
}

try {
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tempRoot
    $packageRoot = Join-Path $tempRoot 'ch12-practice'
    $manifestPath = Join-Path $packageRoot 'manifest-sha256.csv'
    $manifest = Import-Csv -LiteralPath $manifestPath

    foreach ($row in $manifest) {
        $file = Join-Path $packageRoot $row.path.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Manifest file missing: $($row.path)"
        }
        if ((Get-Item -LiteralPath $file).Length -ne [int64]$row.size_bytes) {
            throw "Size mismatch: $($row.path)"
        }
        $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $row.sha256) {
            throw "SHA-256 mismatch: $($row.path)"
        }
    }

    $requiredFiles = @(
        'README.md',
        '04_jamovi\ch12_starter.omv',
        '05_worksheet\analysis-record.md',
        '06_R\README_R.md',
        '06_R\check_packages.R',
        '06_R\run_quick_analysis.R',
        '06_R\run_full_analysis.R',
        '06_R\analysis_pipeline.R',
        '06_R\05_tables_figures.R'
    )
    foreach ($relativePath in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $relativePath) -PathType Leaf)) {
            throw "Required package file missing: $relativePath"
        }
    }

    $expectedRows = @{
        '01_raw\SYNTHETIC_00_roster_raw.csv' = 186
        '01_raw\SYNTHETIC_01_T1_survey_raw.csv' = 183
        '01_raw\SYNTHETIC_02_T2_survey_raw.csv' = 169
        '01_raw\SYNTHETIC_03_exam_scores_raw.csv' = 186
        '03_analysis-ready\ch12_analysis_ready.csv' = 162
    }
    foreach ($relativePath in $expectedRows.Keys) {
        $rows = @(Import-Csv -LiteralPath (Join-Path $packageRoot $relativePath))
        if ($rows.Count -ne $expectedRows[$relativePath]) {
            throw "Row count mismatch: $relativePath"
        }
    }

    $analysisRows = @(Import-Csv -LiteralPath (Join-Path $packageRoot '03_analysis-ready\ch12_analysis_ready.csv'))
    if (@($analysisRows | Where-Object { $_.synthetic_flag -ne '1' }).Count -ne 0) {
        throw 'The analysis-ready data contains a row without synthetic_flag = 1.'
    }

    [pscustomobject]@{
        Zip = $zipPath
        ManifestFiles = $manifest.Count
        AnalysisRows = $analysisRows.Count
        RFilesPresent = $true
        AllSynthetic = $true
        HashesVerified = $true
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
