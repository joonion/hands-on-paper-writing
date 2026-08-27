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
$contentPages = @('index.html', 'about.html') + @(1..12 | ForEach-Object { 'chapters/ch{0:d2}.html' -f $_ })
$errors = [System.Collections.Generic.List[string]]::new()
$pageResults = @()
$imagesMissingAlt = 0
$downloadLinksChecked = 0
$expectedSocialImage = ([uri]::new($baseUri, 'assets/social-card.png')).AbsoluteUri
$expectedManifest = ([uri]::new($baseUri, 'site.webmanifest')).AbsoluteUri
$expectedAppleTouchIcon = ([uri]::new($baseUri, 'assets/apple-touch-icon.png')).AbsoluteUri

function Get-PngDimensions {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
    if ($bytes.Length -lt 24) {
        throw "PNG file is too short: $Path"
    }
    for ($index = 0; $index -lt $signature.Length; $index++) {
        if ($bytes[$index] -ne $signature[$index]) {
            throw "Invalid PNG signature: $Path"
        }
    }

    [pscustomobject]@{
        Width = [System.Net.IPAddress]::NetworkToHostOrder([System.BitConverter]::ToInt32($bytes, 16))
        Height = [System.Net.IPAddress]::NetworkToHostOrder([System.BitConverter]::ToInt32($bytes, 20))
    }
}

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
    $ogImage = [regex]::Match(
        $html,
        '(?is)<meta\s+property="og:image"\s+content="([^"]*)"'
    ).Groups[1].Value.Trim()
    $ogImageAlt = [System.Net.WebUtility]::HtmlDecode(
        [regex]::Match($html, '(?is)<meta\s+property="og:image:alt"\s+content="([^"]*)"').Groups[1].Value.Trim()
    )
    $twitterImage = [regex]::Match(
        $html,
        '(?is)<meta\s+name="twitter:image"\s+content="([^"]*)"'
    ).Groups[1].Value.Trim()
    $twitterImageAlt = [System.Net.WebUtility]::HtmlDecode(
        [regex]::Match($html, '(?is)<meta\s+name="twitter:image:alt"\s+content="([^"]*)"').Groups[1].Value.Trim()
    )
    $themeColor = [regex]::Match(
        $html,
        '(?is)<meta\s+name="theme-color"\s+content="([^"]*)"'
    ).Groups[1].Value.Trim()
    $manifestHref = [regex]::Match(
        $html,
        '(?is)<link\s+rel="manifest"[^>]+href="([^"]+)"'
    ).Groups[1].Value.Trim()
    $appleTouchIcon = [regex]::Match(
        $html,
        '(?is)<link\s+rel="apple-touch-icon"[^>]+href="([^"]+)"'
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
    elseif ($twitterCard -ne 'summary_large_image') {
        $errors.Add("Expected summary_large_image Twitter Card: $relativePath -> $twitterCard")
    }
    if ($ogImage -ne $expectedSocialImage -or $twitterImage -ne $expectedSocialImage) {
        $errors.Add("Social preview image mismatch: $relativePath")
    }
    if ([string]::IsNullOrWhiteSpace($ogImageAlt) -or [string]::IsNullOrWhiteSpace($twitterImageAlt)) {
        $errors.Add("Missing social preview image alt text: $relativePath")
    }
    if ($themeColor -ne '#2780e3') {
        $errors.Add("Theme color mismatch: $relativePath -> $themeColor")
    }
    if ($manifestHref -ne $expectedManifest) {
        $errors.Add("Manifest link mismatch: $relativePath -> $manifestHref")
    }
    if ($appleTouchIcon -ne $expectedAppleTouchIcon) {
        $errors.Add("Apple touch icon mismatch: $relativePath -> $appleTouchIcon")
    }
    if ($html -notmatch '(?is)<html\b[^>]*\blang="ko"') {
        $errors.Add("Missing Korean document language: $relativePath")
    }
    if ($html -notmatch '(?is)<link\b[^>]*\brel="icon"') {
        $errors.Add("Missing favicon link: $relativePath")
    }
    if ([regex]::IsMatch($html, '(?is)<meta\s+name="robots"\s+content="[^"]*noindex')) {
        $errors.Add("Unexpected noindex directive: $relativePath")
    }
    if ([regex]::Matches($html, '(?is)<h1\b').Count -ne 1) {
        $errors.Add("Expected exactly one h1: $relativePath")
    }
    foreach ($imageMatch in [regex]::Matches($html, '(?is)<img\b[^>]*>')) {
        if ($imageMatch.Value -notmatch '(?is)\balt\s*=') {
            $imagesMissingAlt++
            $errors.Add("Image missing alt attribute: $relativePath -> $($imageMatch.Value)")
        }
    }
    $downloadLinksChecked += [regex]::Matches($html, '(?is)<a\b[^>]*\bdownload(?:\s*=|\s|>)').Count

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

$manifestPath = Join-Path $siteRoot 'site.webmanifest'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $errors.Add('Missing site.webmanifest')
}
else {
    try {
        $manifest = Get-Content -Raw -Encoding utf8 -LiteralPath $manifestPath | ConvertFrom-Json
        if ($manifest.lang -ne 'ko' -or $manifest.theme_color -ne '#2780e3') {
            $errors.Add('Manifest language or theme color mismatch')
        }
        if (@($manifest.icons).Count -ne 2) {
            $errors.Add("Expected 2 manifest icons, found $(@($manifest.icons).Count)")
        }
    }
    catch {
        $errors.Add("Invalid site.webmanifest: $($_.Exception.Message)")
    }
}

$expectedPngAssets = @{
    'assets/social-card.png' = @(1200, 630)
    'assets/apple-touch-icon.png' = @(180, 180)
    'assets/icon-192.png' = @(192, 192)
    'assets/icon-512.png' = @(512, 512)
}
foreach ($assetEntry in $expectedPngAssets.GetEnumerator()) {
    $assetPath = Join-Path $siteRoot $assetEntry.Key
    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
        $errors.Add("Missing image asset: $($assetEntry.Key)")
        continue
    }
    try {
        $dimensions = Get-PngDimensions -Path $assetPath
        if ($dimensions.Width -ne $assetEntry.Value[0] -or $dimensions.Height -ne $assetEntry.Value[1]) {
            $errors.Add("Image dimensions mismatch: $($assetEntry.Key) -> $($dimensions.Width)x$($dimensions.Height)")
        }
    }
    catch {
        $errors.Add($_.Exception.Message)
    }
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
    SocialPreviewImages = @($pageResults).Count
    PwaImageAssets = $expectedPngAssets.Count
    ImagesMissingAlt = $imagesMissingAlt
    DownloadLinksChecked = $downloadLinksChecked
    BrokenLocalLinks = $brokenLinks.Count
    Errors = $errors.Count
}

$summary | Format-List
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "ERROR: $_" -ForegroundColor Red }
    exit 1
}
