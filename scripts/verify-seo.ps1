param(
    [string]$SiteDir = (Join-Path (Split-Path -Parent $PSScriptRoot) '_site'),
    [string]$SiteUrl = 'https://joonion.github.io/hands-on-paper-writing/'
)

$ErrorActionPreference = 'Stop'
$siteRoot = [System.IO.Path]::GetFullPath($SiteDir)
if (-not (Test-Path -LiteralPath $siteRoot -PathType Container)) {
    throw "Rendered site directory not found: $siteRoot"
}

$baseUri = [uri]$SiteUrl
$basePath = $baseUri.AbsolutePath.TrimEnd('/') + '/'
$contentPages = @('index.html') + @(1..12 | ForEach-Object { 'chapters/ch{0:d2}.html' -f $_ })
$errors = [System.Collections.Generic.List[string]]::new()
$pageResults = @()

foreach ($relativePath in $contentPages) {
    $localPath = Join-Path $siteRoot $relativePath
    if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        $errors.Add("Missing rendered page: $relativePath")
        continue
    }

    $html = Get-Content -Raw -Encoding utf8 -LiteralPath $localPath
    $title = [System.Net.WebUtility]::HtmlDecode(
        [regex]::Match($html, '(?is)<title>(.*?)</title>').Groups[1].Value.Trim()
    )
    $description = [System.Net.WebUtility]::HtmlDecode(
        [regex]::Match($html, '(?is)<meta\s+name="description"\s+content="([^"]*)"').Groups[1].Value.Trim()
    )
    $canonical = [regex]::Match(
        $html,
        '(?is)<link\s+rel="canonical"\s+href="([^"]+)"'
    ).Groups[1].Value.Trim()
    $ogTitle = [regex]::Match(
        $html,
        '(?is)<meta\s+property="og:title"\s+content="([^"]*)"'
    ).Groups[1].Value.Trim()
    $ogDescription = [regex]::Match(
        $html,
        '(?is)<meta\s+property="og:description"\s+content="([^"]*)"'
    ).Groups[1].Value.Trim()
    $twitterCard = [regex]::Match(
        $html,
        '(?is)<meta\s+name="twitter:card"\s+content="([^"]*)"'
    ).Groups[1].Value.Trim()
    $expectedCanonical = if ($relativePath -eq 'index.html') {
        $baseUri.AbsoluteUri
    }
    else {
        ([uri]::new($baseUri, $relativePath)).AbsoluteUri
    }

    if ([string]::IsNullOrWhiteSpace($title)) {
        $errors.Add("Missing title: $relativePath")
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
        $errors.Add("Missing meta description: $relativePath")
    }
    elseif ($description.Length -lt 50 -or $description.Length -gt 180) {
        $errors.Add("Meta description length outside 50-180 characters: $relativePath")
    }
    if ($canonical -ne $expectedCanonical) {
        $errors.Add("Canonical mismatch: $relativePath -> $canonical")
    }
    if ([string]::IsNullOrWhiteSpace($ogTitle) -or [string]::IsNullOrWhiteSpace($ogDescription)) {
        $errors.Add("Missing Open Graph metadata: $relativePath")
    }
    if ([string]::IsNullOrWhiteSpace($twitterCard)) {
        $errors.Add("Missing Twitter Card metadata: $relativePath")
    }
    if ([regex]::IsMatch($html, '(?is)<meta\s+name="robots"\s+content="[^"]*noindex')) {
        $errors.Add("Unexpected noindex directive: $relativePath")
    }
    if ([regex]::Matches($html, '(?is)<h1\b').Count -ne 1) {
        $errors.Add("Expected exactly one h1: $relativePath")
    }

    $pageResults += [pscustomobject]@{
        Page = $relativePath
        Title = $title
        Description = $description
        Canonical = $canonical
    }
}

$duplicateTitles = @($pageResults | Group-Object Title | Where-Object Count -gt 1)
$duplicateDescriptions = @($pageResults | Group-Object Description | Where-Object Count -gt 1)
foreach ($group in $duplicateTitles) {
    $errors.Add("Duplicate title: $($group.Name)")
}
foreach ($group in $duplicateDescriptions) {
    $errors.Add("Duplicate meta description: $($group.Name)")
}

$sitemapPath = Join-Path $siteRoot 'sitemap.xml'
$sitemapUrls = @()
if (-not (Test-Path -LiteralPath $sitemapPath -PathType Leaf)) {
    $errors.Add('Missing sitemap.xml')
}
else {
    $sitemap = Get-Content -Raw -Encoding utf8 -LiteralPath $sitemapPath
    $sitemapUrls = @(
        [regex]::Matches($sitemap, '(?is)<loc>(.*?)</loc>') |
            ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value.Trim()) }
    )
    if ($sitemapUrls.Count -ne $contentPages.Count) {
        $errors.Add("Expected $($contentPages.Count) sitemap URLs, found $($sitemapUrls.Count)")
    }
    foreach ($page in $pageResults) {
        if ($page.Canonical -notin $sitemapUrls) {
            $errors.Add("Canonical URL missing from sitemap: $($page.Canonical)")
        }
    }
    if (@($sitemapUrls | Where-Object { $_ -match '/404\.html$' }).Count -gt 0) {
        $errors.Add('404.html must not be included in sitemap.xml')
    }
}

$notFoundPath = Join-Path $siteRoot '404.html'
if (-not (Test-Path -LiteralPath $notFoundPath -PathType Leaf)) {
    $errors.Add('Missing 404.html')
}

$brokenLinks = [System.Collections.Generic.HashSet[string]]::new()
foreach ($htmlFile in Get-ChildItem -LiteralPath $siteRoot -Recurse -Filter '*.html' -File) {
    $html = Get-Content -Raw -Encoding utf8 -LiteralPath $htmlFile.FullName
    foreach ($match in [regex]::Matches($html, '(?is)href="([^"]+)"')) {
        $href = [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value.Trim())
        if (
            [string]::IsNullOrWhiteSpace($href) -or
            $href.StartsWith('#') -or
            $href.StartsWith('//') -or
            $href -match '^(?i:https?|mailto|tel|javascript|data):'
        ) {
            continue
        }

        $pathOnly = ($href -split '[?#]', 2)[0]
        if ([string]::IsNullOrWhiteSpace($pathOnly)) {
            continue
        }
        $pathOnly = [uri]::UnescapeDataString($pathOnly)

        if ($pathOnly.StartsWith('/')) {
            if (-not $pathOnly.StartsWith($basePath)) {
                continue
            }
            $relativeTarget = $pathOnly.Substring($basePath.Length)
            $target = Join-Path $siteRoot $relativeTarget
        }
        else {
            $target = Join-Path $htmlFile.DirectoryName $pathOnly
        }

        $target = [System.IO.Path]::GetFullPath($target)
        if ($pathOnly.EndsWith('/')) {
            $target = Join-Path $target 'index.html'
        }
        if (-not (Test-Path -LiteralPath $target)) {
            $brokenLinks.Add("$($htmlFile.FullName.Substring($siteRoot.Length + 1)) -> $href") | Out-Null
        }
    }
}

foreach ($brokenLink in $brokenLinks) {
    $errors.Add("Broken local link: $brokenLink")
}

$summary = [pscustomobject]@{
    Site = $SiteUrl
    ContentPages = $pageResults.Count
    UniqueTitles = @($pageResults.Title | Sort-Object -Unique).Count
    UniqueDescriptions = @($pageResults.Description | Sort-Object -Unique).Count
    SitemapUrls = $sitemapUrls.Count
    Has404 = (Test-Path -LiteralPath $notFoundPath -PathType Leaf)
    BrokenLocalLinks = $brokenLinks.Count
    Errors = $errors.Count
}

$summary | Format-List
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
