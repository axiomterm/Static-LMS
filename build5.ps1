<#
.SYNOPSIS
    Generates the static course site from the .md files in /content.
    Windows PowerShell 5.1 version of build.ps1.

.DESCRIPTION
    Identical to build.ps1, but self-contained for Windows PowerShell 5.1,
    which lacks the ConvertFrom-Markdown cmdlet (PowerShell 7+ only). Instead,
    a small built-in Markdown -> HTML converter (Convert-Markdown) handles the
    Markdown subset this project uses: ATX headings (with auto ids), paragraphs,
    ordered/unordered lists, blockquotes, GFM pipe tables, fenced code blocks,
    horizontal rules, raw HTML passthrough (needed for the ::video blocks), and
    inline bold/italic/strikethrough/code/links/images.

.NOTES
    Runs on Windows PowerShell 5.1 (and also on PowerShell 7+).
    IMPORTANT: this file must be saved as UTF-8 WITH BOM. Windows PowerShell 5.1
    reads BOM-less .ps1 files as ANSI, which corrupts non-ASCII source (e.g. the
    U+FEFF in the front-matter regex below).
    Limitations vs. ConvertFrom-Markdown (Markdig): single-level lists only
    (no nesting), no reference-style links, no setext headings. Enough for
    typical course content; use build.ps1 on PowerShell 7 for full CommonMark.
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    # If set, the build FAILS on an unknown category.
    # By default it only warns (Write-Warning) and skips that chip.
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

# --- Paths -------------------------------------------------------------
$ContentDir   = Join-Path $PSScriptRoot 'content'
$TemplatesDir = Join-Path $PSScriptRoot 'build\templates'
$OutDir       = Join-Path $PSScriptRoot 'wwwroot'
$CoursesDir   = Join-Path $OutDir 'courses'

# NOTE: read files with [IO.File]::ReadAllText (UTF-8 + BOM detection). Windows
# PowerShell 5.1's Get-Content defaults to the ANSI codepage, which mangles
# accents/dots/... in the templates and course content.
$CourseTemplate = [System.IO.File]::ReadAllText((Join-Path $TemplatesDir 'course.html'))
$IndexTemplate  = [System.IO.File]::ReadAllText((Join-Path $TemplatesDir 'index.html'))

# Controlled category vocabulary (slug -> display name, in file order)
$CategoriesFile = Join-Path $ContentDir 'categories.json'
$Categories = [ordered]@{}
if (Test-Path $CategoriesFile) {
    $catObj = [System.IO.File]::ReadAllText($CategoriesFile) | ConvertFrom-Json
    foreach ($p in $catObj.PSObject.Properties) { $Categories[$p.Name] = [string]$p.Value }
} else {
    Write-Warning "$CategoriesFile does not exist; categories will not be validated."
}

New-Item -ItemType Directory -Force -Path $CoursesDir | Out-Null
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Date = (Get-Date).ToString('yyyy-MM-dd HH:mm')

# --- Helper functions ----------------------------------------------------
function Encode([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }

# --- Built-in Markdown -> HTML (replaces ConvertFrom-Markdown on PS 5.1) ---

# HTML-escapes text the way Markdig does inside content (& < > " but not ').
function Get-MdEscaped([string]$s) {
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

# GitHub-style heading id: lowercase, drop punctuation, spaces -> hyphens.
function Get-HeadingSlug([string]$text) {
    $s = $text -replace '[*_`~]', '' -replace '<[^>]+>', ''
    $s = $s.ToLowerInvariant() -replace '[^\p{L}\p{Nd}\s-]', ''
    return ($s.Trim() -replace '\s+', '-')
}

# Inline formatting: code, images, links, bold, italic, strikethrough.
function Convert-MarkdownInline([string]$text) {
    # Pull out inline code spans first so their content isn't formatted/altered.
    $store = @{}
    $rx = [regex]'`([^`\n]+)`'
    while ($true) {
        $m = $rx.Match($text)
        if (-not $m.Success) { break }
        $key = "$([char]27)$($store.Count)$([char]27)"
        $store[$key] = '<code>' + (Get-MdEscaped $m.Groups[1].Value) + '</code>'
        $text = $text.Substring(0, $m.Index) + $key + $text.Substring($m.Index + $m.Length)
    }

    $text = Get-MdEscaped $text

    $text = $text -replace '!\[([^\]]*)\]\(([^)]+)\)', '<img src="$2" alt="$1" />'
    $text = $text -replace '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>'
    $text = $text -replace '\*\*([^*]+)\*\*', '<strong>$1</strong>'
    $text = $text -replace '__([^_]+)__', '<strong>$1</strong>'
    $text = $text -replace '~~([^~]+)~~', '<del>$1</del>'
    $text = $text -replace '(?<!\*)\*([^*\n]+)\*(?!\*)', '<em>$1</em>'
    $text = $text -replace '(?<!_)_([^_\n]+)_(?!_)', '<em>$1</em>'

    foreach ($k in $store.Keys) { $text = $text.Replace($k, $store[$k]) }
    return $text
}

# Splits a GFM table row "| a | b |" into trimmed cells.
function Split-TableRow([string]$row) {
    $r = $row.Trim() -replace '^\|', '' -replace '\|$', ''
    return @($r -split '\|' | ForEach-Object { $_.Trim() })
}

# Converts a Markdown body to HTML. Emits plain <table>/<blockquote> tags so the
# caller's Bootstrap .Replace() styling keeps working.
function Convert-Markdown([string]$markdown) {
    $lines = ($markdown -replace "`r`n", "`n") -split "`n"
    $n = $lines.Count
    $out = New-Object System.Collections.Generic.List[string]
    $i = 0

    while ($i -lt $n) {
        $line = $lines[$i]

        if ($line.Trim() -eq '') { $i++; continue }

        # Raw HTML block (e.g. the injected ::video block): passthrough verbatim.
        if ($line -match '^\s*<') {
            $buf = @()
            while ($i -lt $n -and $lines[$i].Trim() -ne '') { $buf += $lines[$i]; $i++ }
            $out.Add($buf -join "`n")
            continue
        }

        # Fenced code block.
        if ($line -match '^\s*```') {
            $i++
            $code = @()
            while ($i -lt $n -and $lines[$i] -notmatch '^\s*```') { $code += $lines[$i]; $i++ }
            $i++  # skip closing fence
            $escaped = (@($code | ForEach-Object { Get-MdEscaped $_ }) -join "`n")
            $out.Add("<pre><code>$escaped`n</code></pre>")
            continue
        }

        # ATX heading.
        if ($line -match '^(#{1,6})\s+(.*)$') {
            $level = $matches[1].Length
            $htext = ($matches[2].Trim() -replace '\s+#+\s*$', '')
            $out.Add("<h$level id=""$(Get-HeadingSlug $htext)"">$(Convert-MarkdownInline $htext)</h$level>")
            $i++
            continue
        }

        # Horizontal rule.
        if ($line -match '^\s*([-*_])(\s*\1){2,}\s*$') {
            $out.Add('<hr />')
            $i++
            continue
        }

        # Blockquote (recurses on the un-quoted content).
        if ($line -match '^\s*>') {
            $buf = @()
            while ($i -lt $n -and $lines[$i] -match '^\s*>') {
                $buf += ($lines[$i] -replace '^\s*>\s?', '')
                $i++
            }
            $inner = Convert-Markdown ($buf -join "`n")
            $out.Add("<blockquote>`n$inner`n</blockquote>")
            continue
        }

        # GFM pipe table: header row followed by a delimiter row.
        if ($line -match '\|' -and $i + 1 -lt $n -and
            $lines[$i + 1] -match '^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$') {
            $headerCells = Split-TableRow $lines[$i]
            $i += 2
            $rows = @()
            while ($i -lt $n -and $lines[$i].Trim() -ne '' -and $lines[$i] -match '\|') {
                $rows += , (Split-TableRow $lines[$i])
                $i++
            }
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("<table>`n<thead>`n<tr>`n")
            foreach ($c in $headerCells) { [void]$sb.Append("<th>$(Convert-MarkdownInline $c)</th>`n") }
            [void]$sb.Append("</tr>`n</thead>`n<tbody>`n")
            foreach ($row in $rows) {
                [void]$sb.Append("<tr>`n")
                foreach ($c in $row) { [void]$sb.Append("<td>$(Convert-MarkdownInline $c)</td>`n") }
                [void]$sb.Append("</tr>`n")
            }
            [void]$sb.Append("</tbody>`n</table>")
            $out.Add($sb.ToString())
            continue
        }

        # Ordered list.
        if ($line -match '^\s*\d+\.\s+') {
            $items = @()
            while ($i -lt $n -and $lines[$i] -match '^\s*\d+\.\s+(.*)$') {
                $items += (Convert-MarkdownInline $matches[1])
                $i++
            }
            $out.Add("<ol>`n" + (@($items | ForEach-Object { "<li>$_</li>" }) -join "`n") + "`n</ol>")
            continue
        }

        # Unordered list.
        if ($line -match '^\s*[-*+]\s+') {
            $items = @()
            while ($i -lt $n -and $lines[$i] -match '^\s*[-*+]\s+(.*)$') {
                $items += (Convert-MarkdownInline $matches[1])
                $i++
            }
            $out.Add("<ul>`n" + (@($items | ForEach-Object { "<li>$_</li>" }) -join "`n") + "`n</ul>")
            continue
        }

        # Paragraph: gather lines until a blank line or the start of another block.
        $para = @()
        while ($i -lt $n -and $lines[$i].Trim() -ne '' -and
               $lines[$i] -notmatch '^\s*<' -and
               $lines[$i] -notmatch '^#{1,6}\s+' -and
               $lines[$i] -notmatch '^\s*>' -and
               $lines[$i] -notmatch '^\s*```' -and
               $lines[$i] -notmatch '^\s*\d+\.\s+' -and
               $lines[$i] -notmatch '^\s*[-*+]\s+') {
            $para += $lines[$i]
            $i++
        }
        $out.Add("<p>$(Convert-MarkdownInline ($para -join "`n"))</p>")
    }

    return ($out -join "`n")
}

function Get-FrontMatter([string]$text) {
    # Returns @{ Meta = [ordered]@{...}; Body = '...' }. The ^﻿? tolerates a
    # stray leading BOM (this file is UTF-8 with BOM; see .NOTES).
    $meta = [ordered]@{}
    $body = $text

    $m = [regex]::Match($text, '(?s)^﻿?\s*---\r?\n(.*?)\r?\n---\r?\n?(.*)$')
    if ($m.Success) {
        $body = $m.Groups[2].Value
        $currentList = $null
        foreach ($line in ($m.Groups[1].Value -split '\r?\n')) {
            if ($line.Trim() -eq '') { continue }
            if ($line -match '^\s*-\s+(.*)$') {
                # list item
                if ($currentList) {
                    $val = $matches[1].Trim().Trim('"').Trim("'")
                    $meta[$currentList] = @($meta[$currentList]) + $val
                }
                continue
            }
            if ($line -match '^([A-Za-z_][\w-]*):\s*(.*)$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim()
                if ($val -eq '') {
                    # key with no value -> likely a list on the following lines
                    $currentList = $key
                    $meta[$key] = @()
                } else {
                    $currentList = $null
                    $v = $val.Trim('"').Trim("'")
                    if ($v -match '^\[(.*)\]$') {
                        # inline list: [a, b, c]
                        $arr = @()
                        foreach ($p in ($matches[1] -split ',')) {
                            $p = $p.Trim().Trim('"').Trim("'")
                            if ($p -ne '') { $arr += $p }
                        }
                        $meta[$key] = $arr
                    } else {
                        $meta[$key] = $v
                    }
                }
            }
        }
    }
    return @{ Meta = $meta; Body = $body }
}

function Get-VideoBlock($videoPath) {
    if ([string]::IsNullOrWhiteSpace($videoPath)) { return '' }
    $src = '../' + ($videoPath -replace '^/', '')
    $ext = [System.IO.Path]::GetExtension($videoPath).ToLowerInvariant()
    $type = switch ($ext) {
        '.webm' { 'video/webm' }
        '.ogg'  { 'video/ogg' }
        '.ogv'  { 'video/ogg' }
        default { 'video/mp4' }
    }
    return @"
<div class="ratio ratio-16x9 mx-auto my-3" style="max-width: 42rem;">
      <video controls preload="metadata" class="rounded">
        <source src="$src" type="$type">
        Your browser does not support HTML5 video playback.
      </video>
    </div>
"@
}

function Get-DocumentsBlock($docs) {
    if (-not $docs -or @($docs).Count -eq 0) { return '' }
    $icon = '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/></svg>'
    $items = foreach ($d in @($docs)) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        $href = '../' + ($d -replace '^/', '')
        $name = Encode([System.IO.Path]::GetFileName($d))
        "        <li class=""list-group-item""><a href=""$href"" download class=""icon-link"">$icon $name</a></li>"
    }
    return @"
<div class="card mb-4 documents">
      <div class="card-header">Documents</div>
      <ul class="list-group list-group-flush">
$($items -join "`n")
      </ul>
    </div>
"@
}

function Get-CategoryBadges($slugs, $map) {
    if (-not $slugs -or @($slugs).Count -eq 0) { return '' }
    $badges = foreach ($s in @($slugs)) {
        $name = if ($map.Contains($s)) { $map[$s] } else { $s }
        "<span class=""badge rounded-pill text-bg-light border"">$(Encode $name)</span>"
    }
    return ($badges -join ' ')
}

# --- Clean previous output ------------------------------------------------
Get-ChildItem -Path $CoursesDir -Filter '*.html' -ErrorAction SilentlyContinue | Remove-Item -Force

# --- Process courses -------------------------------------------------------
$courses = @()
$mdFiles = Get-ChildItem -Path $ContentDir -Filter '*.md' -File | Sort-Object Name

if (-not $mdFiles) { Write-Warning "No .md files found in $ContentDir"; }

foreach ($file in $mdFiles) {
    $raw = [System.IO.File]::ReadAllText($file.FullName)
    $fm  = Get-FrontMatter $raw
    $meta = $fm.Meta

    $id = if ($meta.id) { $meta.id } else { $file.BaseName }
    $id = ($id -replace '[^\w-]', '-').Trim('-').ToLowerInvariant()
    $title = if ($meta.title) { $meta.title } else { $file.BaseName }
    $description = if ($meta.description) { $meta.description } else { '' }
    # Course date (YYYY-MM-DD): sorts the catalog (newest first)
    $dateStr = if ($meta.date) { [string]$meta.date } else { '' }
    $dateObj = [datetime]::MinValue
    if ($dateStr -ne '') {
        $tmp = [datetime]::MinValue
        if ([datetime]::TryParse($dateStr, [ref]$tmp)) { $dateObj = $tmp }
        else { Write-Warning "Invalid date '$dateStr' in $($file.Name) (use YYYY-MM-DD)." }
    }

    # Categories: validate against the controlled vocabulary
    # NOTE: named $courseCategories (not $categories) because PowerShell variable
    # names are case-insensitive, and $categories would collide with $Categories
    # (the master vocabulary loaded above).
    $courseCategories = @()
    if ($meta.categories) {
        foreach ($c in @($meta.categories)) {
            $slug = ([string]$c).Trim().ToLowerInvariant()
            if ($slug -eq '') { continue }
            if ($Categories.Count -gt 0 -and -not $Categories.Contains($slug)) {
                $msg = "Unknown category '$slug' in $($file.Name). Add it to content/categories.json or fix the slug."
                if ($Strict) { throw $msg } else { Write-Warning $msg; continue }
            }
            if ($courseCategories -notcontains $slug) { $courseCategories += $slug }
        }
    }

    # Replace ::video <path> directives interspersed in the Markdown body
    $bodyMarkdown = [regex]::Replace($fm.Body, '(?m)^[ \t]*::video[ \t]+(\S+)', {
        param($m)
        "`n" + (Get-VideoBlock $m.Groups[1].Value) + "`n"
    })
    $contentHtml = Convert-Markdown $bodyMarkdown
    # Style Markdown elements with Bootstrap classes
    $contentHtml = $contentHtml.Replace('<table>', '<div class="table-responsive"><table class="table table-bordered">').Replace('</table>', '</table></div>')
    $contentHtml = $contentHtml.Replace('<blockquote>', '<blockquote class="blockquote border-start border-3 ps-3 text-secondary">')
    $documentsBlock = Get-DocumentsBlock $meta.documents

    $html = $CourseTemplate
    $html = $html.Replace('{{id}}',          $id)
    $html = $html.Replace('{{title}}',       (Encode $title))
    $html = $html.Replace('{{description}}', (Encode $description))
    $categoryBadges = Get-CategoryBadges $courseCategories $Categories
    $categoriesHtml = if ($categoryBadges) { "<div class=""mb-4"">$categoryBadges</div>" } else { '' }
    $html = $html.Replace('{{categories}}',  $categoriesHtml)
    $html = $html.Replace('{{content}}',     $contentHtml)
    $html = $html.Replace('{{documents}}',   $documentsBlock)
    $html = $html.Replace('{{date}}',        $Date)

    $outputFile = Join-Path $CoursesDir "$id.html"
    [System.IO.File]::WriteAllText($outputFile, $html, $Utf8NoBom)

    $courses += [pscustomobject]@{
        Id          = $id
        Title       = $title
        Description = $description
        DateStr     = $dateStr
        DateObj     = $dateObj
        Categories  = $courseCategories
    }
    Write-Host "  [course] $($file.Name) -> courses/$id.html"
}

# --- Generate index --------------------------------------------------------
$sortedCourses = $courses | Sort-Object @{Expression = 'DateObj'; Descending = $true}, @{Expression = 'Title'; Descending = $false}
$cards = foreach ($c in $sortedCourses) {
    $dataCategories = (@($c.Categories) -join ' ')
    $badges = Get-CategoryBadges $c.Categories $Categories
    $dateHtml = if ($c.DateStr) { "Published on $(Encode $c.DateStr)" } else { '' }
    @"
<div class="col course-item" data-categories="$dataCategories" data-course-id="$($c.Id)" data-date="$($c.DateStr)">
        <div class="card h-100">
          <div class="card-header d-flex justify-content-between align-items-start gap-2">
            <h2 class="h5 mb-0">$(Encode $c.Title)</h2>
          </div>
          <div class="card-body d-flex flex-column">
            <p class="card-text text-secondary">$(Encode $c.Description)</p>
            <div class="mt-auto">$badges</div>
          </div>
          <div class="card-footer d-flex justify-content-between align-items-center">
            <small class="text-secondary">$dateHtml</small>
            <a href="courses/$($c.Id).html" class="btn btn-primary btn-sm">Go to course</a>
          </div>
        </div>
      </div>
"@
}

# Filter box: category dropdown (ALL, in master order) + sort control
if ($courses.Count -gt 0) {
    $categoryDropdown = ''
    if ($Categories.Count -gt 0) {
        $items = foreach ($slug in $Categories.Keys) {
            "                <li><label class=""dropdown-item""><input class=""form-check-input me-2"" type=""checkbox"" value=""$slug""> $(Encode $Categories[$slug])</label></li>"
        }
        $categoryDropdown = @"
<div class="d-flex align-items-center gap-2">
            <label class="form-label mb-0 text-secondary">Category:</label>
            <div class="dropdown category-filter">
              <button class="btn btn-outline-secondary btn-sm dropdown-toggle" type="button" data-bs-toggle="dropdown" data-bs-auto-close="outside" data-base="Filter by category">Filter by category</button>
              <ul class="dropdown-menu p-2">
$($items -join "`n")
              </ul>
            </div>
          </div>
"@
    }
    $filtersHtml = @"
<div class="card mb-4">
        <div class="card-body d-flex flex-wrap align-items-center gap-3">
          $categoryDropdown
          <div class="d-flex align-items-center gap-2">
            <label class="form-label mb-0 text-secondary">Courses:</label>
            <select class="form-select form-select-sm w-auto course-filter">
              <option value="all">All</option>
              <option value="pending">Pending</option>
              <option value="completed">Completed</option>
            </select>
          </div>
          <div class="d-flex align-items-center gap-2 ms-auto">
            <label class="form-label mb-0 text-secondary">Sort:</label>
            <select class="form-select form-select-sm w-auto course-sort">
              <option value="date">Date (newest first)</option>
              <option value="alphabetical">Alphabetical (A-Z)</option>
            </select>
          </div>
        </div>
      </div>
"@
} else {
    $filtersHtml = ''
}

$indexHtml = $IndexTemplate
$indexHtml = $indexHtml.Replace('{{filters}}', $filtersHtml)
$indexHtml = $indexHtml.Replace('{{cards}}',   ($cards -join "`n      "))
$indexHtml = $indexHtml.Replace('{{total}}',   [string]$courses.Count)
$indexHtml = $indexHtml.Replace('{{date}}',    $Date)
[System.IO.File]::WriteAllText((Join-Path $OutDir 'index.html'), $indexHtml, $Utf8NoBom)

Write-Host ""
Write-Host "OK: $($courses.Count) course(s) generated in $OutDir" -ForegroundColor Green
