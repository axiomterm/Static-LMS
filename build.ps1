<#
.SYNOPSIS
    Generates the static course site from the .md files in /content.

.DESCRIPTION
    For each content/<id>.md:
      - splits the YAML front matter from the Markdown body,
      - converts the body to HTML with ConvertFrom-Markdown (PowerShell 7+),
      - fills in the build/templates/course.html template,
      - writes wwwroot/courses/<id>.html.
    It also generates wwwroot/index.html with the catalog.

.NOTES
    Requires PowerShell 7 or later (for ConvertFrom-Markdown).
#>

#Requires -Version 7.0
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

$CourseTemplate = Get-Content (Join-Path $TemplatesDir 'course.html') -Raw
$IndexTemplate  = Get-Content (Join-Path $TemplatesDir 'index.html') -Raw

# Controlled category vocabulary (slug -> display name, in file order)
$CategoriesFile = Join-Path $ContentDir 'categories.json'
$Categories = [ordered]@{}
if (Test-Path $CategoriesFile) {
    $catObj = Get-Content $CategoriesFile -Raw | ConvertFrom-Json
    foreach ($p in $catObj.PSObject.Properties) { $Categories[$p.Name] = [string]$p.Value }
} else {
    Write-Warning "$CategoriesFile does not exist; categories will not be validated."
}

New-Item -ItemType Directory -Force -Path $CoursesDir | Out-Null
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Date = (Get-Date).ToString('yyyy-MM-dd HH:mm')

# --- Helper functions ----------------------------------------------------
function Encode([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }

function Get-FrontMatter([string]$text) {
    # Returns @{ Meta = [ordered]@{...}; Body = '...' }
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
    $raw = Get-Content $file.FullName -Raw
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
    $contentHtml = (ConvertFrom-Markdown -InputObject $bodyMarkdown).Html
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
