param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetFullPath($RepoRoot)
$downloadDir = Join-Path $repo 'downloads'
$outputZip = Join-Path $downloadDir 'ch12-practice.zip'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ch12-practice-" + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $tempRoot 'ch12-practice'
$tempZip = Join-Path $tempRoot 'ch12-practice.zip'

$copies = @(
    @{ Source = 'analysis\06_student\README.md'; Destination = 'README.md' },
    @{ Source = 'analysis\01_raw\SYNTHETIC_00_roster_raw.csv'; Destination = '01_raw\SYNTHETIC_00_roster_raw.csv' },
    @{ Source = 'analysis\01_raw\SYNTHETIC_01_T1_survey_raw.csv'; Destination = '01_raw\SYNTHETIC_01_T1_survey_raw.csv' },
    @{ Source = 'analysis\01_raw\SYNTHETIC_02_T2_survey_raw.csv'; Destination = '01_raw\SYNTHETIC_02_T2_survey_raw.csv' },
    @{ Source = 'analysis\01_raw\SYNTHETIC_03_exam_scores_raw.csv'; Destination = '01_raw\SYNTHETIC_03_exam_scores_raw.csv' },
    @{ Source = 'analysis\01_raw\SYNTHETIC_codebook.xlsx'; Destination = '02_codebook\SYNTHETIC_codebook.xlsx' },
    @{ Source = 'analysis\06_student\SYNTHETIC_codebook.md'; Destination = '02_codebook\SYNTHETIC_codebook.md' },
    @{ Source = 'analysis\06_student\ch12_analysis_ready.csv'; Destination = '03_analysis-ready\ch12_analysis_ready.csv' },
    @{ Source = 'analysis\06_student\ch12_starter.omv'; Destination = '04_jamovi\ch12_starter.omv' },
    @{ Source = 'analysis\06_student\analysis-record.md'; Destination = '05_worksheet\analysis-record.md' },
    @{ Source = 'analysis\06_student\06_R\README_R.md'; Destination = '06_R\README_R.md' },
    @{ Source = 'analysis\06_student\06_R\check_packages.R'; Destination = '06_R\check_packages.R' },
    @{ Source = 'analysis\06_student\06_R\run_quick_analysis.R'; Destination = '06_R\run_quick_analysis.R' },
    @{ Source = 'analysis\06_student\06_R\run_full_analysis.R'; Destination = '06_R\run_full_analysis.R' },
    @{ Source = 'analysis\02_scripts\analysis_pipeline.R'; Destination = '06_R\analysis_pipeline.R' },
    @{ Source = 'analysis\02_scripts\tables_figures.R'; Destination = '06_R\tables_figures.R' }
)

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

    foreach ($item in $copies) {
        $source = Join-Path $repo $item.Source
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "필수 파일을 찾지 못했습니다: $source"
        }
        $destination = Join-Path $packageRoot $item.Destination
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
    }

    $manifest = Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                path = $_.FullName.Substring($packageRoot.Length).TrimStart('\').Replace('\', '/')
                size_bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
    $manifestPath = Join-Path $packageRoot 'manifest-sha256.csv'
    $manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

    Compress-Archive -LiteralPath $packageRoot -DestinationPath $tempZip -CompressionLevel Optimal
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
    Move-Item -LiteralPath $tempZip -Destination $outputZip -Force
    Write-Output $outputZip
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
