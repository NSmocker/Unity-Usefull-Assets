$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$env:LC_ALL = 'C.UTF-8'
$env:LANG = 'C.UTF-8'

trap {
    Write-Host ''
    Write-Host 'ERROR:' -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    Write-Host ''
    Read-Host 'Press Enter to close'
    exit 1
}

Set-Location -LiteralPath $PSScriptRoot

Write-Host 'Starting batch commit helper...'
Write-Host "Repository: $PSScriptRoot"

$batchSizeText = Read-Host 'Enter number of files to commit in this batch'
$batchSize = 0
if (-not [int]::TryParse($batchSizeText, [ref]$batchSize) -or $batchSize -le 0) {
    throw "Invalid file count: $batchSizeText"
}
$script:batchSize = $batchSize
Write-Host "Batch size: $batchSize"

Write-Host 'Detecting current branch...'
$branch = (git branch --show-current).Trim()
if (-not $branch) {
    throw 'Cannot determine current Git branch.'
}
Write-Host "Current branch: $branch"

Write-Host 'Checking for already staged files...'
$stagedBefore = [int](git diff --cached --name-only | Measure-Object -Line).Lines
if ($stagedBefore -ne 0) {
    throw "There are already $stagedBefore staged files. Commit or unstage them before running this script."
}

function Test-LfsCandidate([string]$path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $size = (Get-Item -LiteralPath $path).Length
        if ($size -ge 100MB) { return $true }

        $attr = git check-attr filter -- "$path"
        if ($attr -match ': filter: lfs$') { return $true }
    }

    return $false
}

function Add-Candidate([string]$path, [string]$phase) {
    if (-not $path) { return }
    $path = $path.Trim()
    if ($path.StartsWith('"') -and $path.EndsWith('"')) {
        $path = $path.Substring(1, $path.Length - 2)
    }

    if ($script:batch.Count -ge $script:batchSize) { return }
    if (-not $script:seen.Add($path)) { return }
    if ($script:skippedSet.Contains($path)) { return }

    $script:checkedCount++
    Write-Host ("[{0}] {1} | selected {2}/{3}: {4}" -f $script:checkedCount, $phase, $script:batch.Count, $script:batchSize, $path)

    if (Test-LfsCandidate $path) {
        Write-Host "Skipped LFS/large-file candidate: $path"
        [void]$script:skippedSet.Add($path)
        return
    }

    $script:batch.Add($path)
}

function Select-Batch {
    $script:batch = New-Object System.Collections.Generic.List[string]
    $script:seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $script:checkedCount = 0

    Write-Host 'Scanning changed files without sorting...'
    Write-Host 'Reading modified/added tracked files...'
    foreach ($path in git -c core.quotepath=false diff --name-only --diff-filter=ACMRTUXB HEAD) {
        Add-Candidate $path 'tracked'
        if ($script:batch.Count -ge $script:batchSize) { break }
    }

    if ($script:batch.Count -lt $script:batchSize) {
        Write-Host 'Reading deleted tracked files...'
        foreach ($path in git -c core.quotepath=false diff --name-only --diff-filter=D HEAD) {
            Add-Candidate $path 'deleted'
            if ($script:batch.Count -ge $script:batchSize) { break }
        }
    }

    if ($script:batch.Count -lt $script:batchSize) {
        Write-Host 'Reading untracked non-ignored files...'
        foreach ($path in git -c core.quotepath=false ls-files --others --exclude-standard) {
            Add-Candidate $path 'untracked'
            if ($script:batch.Count -ge $script:batchSize) { break }
        }
    }

    Write-Host ("Checked {0} path(s), selected {1} file(s)." -f $script:checkedCount, $script:batch.Count)
    return $script:batch
}

$script:skippedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$batchNumber = 1

while ($true) {
    Write-Host ''
    Write-Host "===== Batch $batchNumber ====="
    $currentBatch = @(Select-Batch)

    if ($currentBatch.Count -eq 0) {
        Write-Host 'No non-LFS changes found to commit.'
        break
    }

    Write-Host "Selected $($currentBatch.Count) file(s) for this commit."
    Write-Host 'Staging selected files...'
    $pathspecFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllLines($pathspecFile, [string[]]$currentBatch, [System.Text.UTF8Encoding]::new($false))
        git add --pathspec-from-file="$pathspecFile"
    }
    finally {
        Remove-Item -LiteralPath $pathspecFile -Force -ErrorAction SilentlyContinue
    }

    $stagedCount = [int](git diff --cached --name-only | Measure-Object -Line).Lines
    if ($stagedCount -eq 0) {
        throw 'No files were staged.'
    }
    Write-Host "Staged $stagedCount file(s)."

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $message = "Batch ${timestamp} #${batchNumber}: add $stagedCount Unity project changes"

    Write-Host "Creating commit: $message"
    git commit -m $message
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }

    $head = (git rev-parse HEAD).Trim()
    Write-Host "Committed $head with $stagedCount files."

    Write-Host "Pushing to origin/$branch..."
    git push origin $branch
    if ($LASTEXITCODE -ne 0) { throw 'git push failed.' }

    Write-Host 'Verifying remote branch SHA...'
    $remoteSha = ((git ls-remote origin "refs/heads/$branch") -split '\s+')[0]
    if ($remoteSha -ne $head) {
        throw "Remote verification failed. Local HEAD is $head, origin/$branch is $remoteSha."
    }

    Write-Host "Pushed and verified $head on origin/$branch."
    $batchNumber++
}

if ($script:skippedSet.Count -gt 0) {
    $skipFile = Join-Path (Get-Location) 'lfs-skipped-files.txt'
    $script:skippedSet | Sort-Object | Set-Content -LiteralPath $skipFile -Encoding UTF8
    Write-Host ("Skipped {0} LFS/large-file candidate(s). See {1}" -f $script:skippedSet.Count, $skipFile)
}

Write-Host ''
Read-Host 'Done. Press Enter to close'
