<#
.SYNOPSIS
    Compares two Blackboard schema documentation folders and reports differences.

.PARAMETER Path1
    Path to the first (older) schema folder, e.g. .\schema-4000.17.0

.PARAMETER Path2
    Path to the second (newer) schema folder, e.g. .\schema-4000.19.0

.PARAMETER OutputPath
    Path for the output report. Defaults to .\schema-diff-report.txt

.PARAMETER HtmlOnly
    If set, only compares .html files (skips images, CSS, JS)

.EXAMPLE
    .\Compare-SchemaDirs.ps1 -Path1 .\schema-4000.17.0 -Path2 .\schema-4000.19.0 -HtmlOnly
#>

param(
    [Parameter(Mandatory)]
    [string]$Path1,

    [Parameter(Mandatory)]
    [string]$Path2,

    [string]$OutputPath = ".\schema-diff-report.txt",

    [switch]$HtmlOnly
)

function Get-DirEntries {
    param([string]$BasePath, [switch]$HtmlOnly)

    $entries = @{}
    $filter  = if ($HtmlOnly) { "*.html" } else { "*.*" }

    Get-ChildItem -Path $BasePath -Recurse -File -Filter $filter | ForEach-Object {
        # Store with a relative key so paths from both dirs are comparable
        $relPath = $_.FullName.Substring($BasePath.TrimEnd('\').Length + 1)
        $entries[$relPath] = @{
            Content  = Get-Content -Path $_.FullName -Raw -Encoding UTF8
            FullPath = $_.FullName
        }
    }

    return $entries
}

function Get-TableData {
    param([string]$Html)

    $tablePattern = '(?s)<table title="Columns">(.+?)</table>'
    if ($Html -match $tablePattern) {
        return $Matches[1]
    }
    return $null
}

function Parse-ColumnRows {
    param([string]$TableHtml)

    $columns     = [ordered]@{}
    $rowPattern  = '(?s)<tr>\s*<td><a name="column-([^"]+)">[^<]+</a></td>\s*<td>([^<]+)</td>\s*<td>([^<]*)</td>\s*<td[^>]*>(.*?)</td>\s*<td>([^<]*)</td>\s*<td>([^<]*)</td>\s*<td>([^<]*)</td>'

    $allMatches = [regex]::Matches($TableHtml, $rowPattern)

    foreach ($m in $allMatches) {
        $colName = $m.Groups[1].Value.Trim()
        $columns[$colName] = @{
            DataType        = $m.Groups[2].Value.Trim()
            Default         = $m.Groups[3].Value.Trim()
            ValueConstraint = ($m.Groups[4].Value -replace '\s+', ' ').Trim()
            Identity        = $m.Groups[6].Value.Trim()
            Nullable        = $m.Groups[7].Value.Trim()
        }
    }

    return $columns
}

function Get-ColumnOrder {
    param([string]$TableHtml)

    $order = @()
    $namePattern = '<a name="column-([^"]+)">'
    [regex]::Matches($TableHtml, $namePattern) | ForEach-Object {
        $order += $_.Groups[1].Value.Trim()
    }
    return $order
}

function Compare-SchemaPage {
    param(
        [string]$FileName,
        [string]$Html1,
        [string]$Html2
    )

    $changes = @()

    $table1 = Get-TableData -Html $Html1
    $table2 = Get-TableData -Html $Html2

    if (-not $table1 -or -not $table2) {
        if ($Html1 -ne $Html2) {
            $changes += "  [CONTENT CHANGED] (non-column page, manual review recommended)"
        }
        return $changes
    }

    $cols1  = Parse-ColumnRows -TableHtml $table1
    $cols2  = Parse-ColumnRows -TableHtml $table2
    $order1 = Get-ColumnOrder -TableHtml $table1
    $order2 = Get-ColumnOrder -TableHtml $table2

    # Column order changed?
    $common1 = $order1 | Where-Object { $cols2.ContainsKey($_) }
    $common2 = $order2 | Where-Object { $cols1.ContainsKey($_) }
    if (($common1 -join ',') -ne ($common2 -join ',')) {
        $changes += "  [ORDER CHANGED]    columns reordered"
        $changes += "    was : $($common1 -join ', ')"
        $changes += "    now : $($common2 -join ', ')"
    }

    # Columns removed
    foreach ($col in $order1) {
        if (-not $cols2.ContainsKey($col)) {
            $dt = $cols1[$col].DataType
            $nl = $cols1[$col].Nullable
            $changes += "  [COLUMN REMOVED]   $col  type=$dt  nullable=$nl"
        }
    }

    # Columns added
    foreach ($col in $order2) {
        if (-not $cols1.ContainsKey($col)) {
            $dt = $cols2[$col].DataType
            $nl = $cols2[$col].Nullable
            $df = $cols2[$col].Default
            $changes += "  [COLUMN ADDED]     $col  type=$dt  nullable=$nl  default='$df'"
        }
    }

    # Columns modified
    $fieldMap = [ordered]@{
        'DataType'        = 'data type'
        'Default'         = 'default'
        'ValueConstraint' = 'value constraint'
        'Identity'        = 'identity'
        'Nullable'        = 'nullable'
    }

    foreach ($col in $order1) {
        if (-not $cols2.ContainsKey($col)) { continue }

        $c1 = $cols1[$col]
        $c2 = $cols2[$col]

        foreach ($field in $fieldMap.Keys) {
            if ($c1[$field] -ne $c2[$field]) {
                $label = $fieldMap[$field]
                $changes += "  [COLUMN MODIFIED]  $col  $label`: '$($c1[$field])' -> '$($c2[$field])'"
            }
        }
    }

    return $changes
}

# ── Main ──────────────────────────────────────────────────────────────────────

# Normalize paths
$Path1 = (Resolve-Path $Path1).Path
$Path2 = (Resolve-Path $Path2).Path

Write-Host "Reading source: $Path1" -ForegroundColor Cyan
$entries1 = Get-DirEntries -BasePath $Path1 -HtmlOnly:$HtmlOnly

Write-Host "Reading target: $Path2" -ForegroundColor Cyan
$entries2 = Get-DirEntries -BasePath $Path2 -HtmlOnly:$HtmlOnly

Write-Host "Comparing $($entries1.Count) source files against $($entries2.Count) target files..." -ForegroundColor Cyan

$report = [System.Text.StringBuilder]::new()
$null   = $report.AppendLine("Blackboard Schema Diff Report")
$null   = $report.AppendLine("  Source : $Path1")
$null   = $report.AppendLine("  Target : $Path2")
$null   = $report.AppendLine("  Run at : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$null   = $report.AppendLine(("-" * 80))

$filesOnlyIn1  = @()
$filesOnlyIn2  = @()
$changedFiles  = @()
$unchangedCount = 0

# Files removed (in source, not in target)
foreach ($file in $entries1.Keys | Sort-Object) {
    if (-not $entries2.ContainsKey($file)) {
        $filesOnlyIn1 += $file
    }
}

# Files added (in target, not in source)
foreach ($file in $entries2.Keys | Sort-Object) {
    if (-not $entries1.ContainsKey($file)) {
        $filesOnlyIn2 += $file
    }
}

# Files present in both — compare
foreach ($file in ($entries1.Keys | Where-Object { $entries2.ContainsKey($_) } | Sort-Object)) {
    if ($entries1[$file].Content -eq $entries2[$file].Content) {
        $unchangedCount++
        continue
    }

    $pageChanges = Compare-SchemaPage `
        -FileName $file `
        -Html1    $entries1[$file].Content `
        -Html2    $entries2[$file].Content

    $changedFiles += [PSCustomObject]@{
        File    = $file
        Changes = $pageChanges
    }
}

# ── Report sections ───────────────────────────────────────────────────────────

$null = $report.AppendLine("")
$null = $report.AppendLine("SUMMARY")
$null = $report.AppendLine("  Unchanged files : $unchangedCount")
$null = $report.AppendLine("  Files removed   : $($filesOnlyIn1.Count)")
$null = $report.AppendLine("  Files added     : $($filesOnlyIn2.Count)")
$null = $report.AppendLine("  Files changed   : $($changedFiles.Count)")

if ($filesOnlyIn1.Count -gt 0) {
    $null = $report.AppendLine("")
    $null = $report.AppendLine("FILES ONLY IN SOURCE (removed tables/pages):")
    foreach ($f in $filesOnlyIn1 | Sort-Object) {
        $null = $report.AppendLine("  - $f")
    }
}

if ($filesOnlyIn2.Count -gt 0) {
    $null = $report.AppendLine("")
    $null = $report.AppendLine("FILES ONLY IN TARGET (new tables/pages):")
    foreach ($f in $filesOnlyIn2 | Sort-Object) {
        $null = $report.AppendLine("  + $f")
    }
}

if ($changedFiles.Count -gt 0) {
    $null = $report.AppendLine("")
    $null = $report.AppendLine("CHANGED FILES:")
    foreach ($cf in $changedFiles | Sort-Object File) {
        $null = $report.AppendLine("")
        $null = $report.AppendLine("  $($cf.File)")
        if ($cf.Changes.Count -gt 0) {
            foreach ($chg in $cf.Changes) {
                $null = $report.AppendLine($chg)
            }
        } else {
            $null = $report.AppendLine("  [CHANGED] content differs but no column-level changes detected (version stamp or description text change)")
        }
    }
}

$null = $report.AppendLine("")
$null = $report.AppendLine(("-" * 80))
$null = $report.AppendLine("End of report")

# ── Output ────────────────────────────────────────────────────────────────────

$reportText = $report.ToString()
$reportText | Out-File -FilePath $OutputPath -Encoding UTF8
Write-Host "`nReport written to: $OutputPath" -ForegroundColor Green
Write-Host $reportText