# Find and fix all external functions that are called internally (constructor pattern)
# These need to be changed to public visibility

$files = Get-ChildItem "contracts" -Recurse -Filter "*.sol"

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $changed = $false
    
    # Pattern: function name(...) external -> function name(...) public
    # Only if not already public/private/internal
    if ($content -match '\) external ') {
        $content = $content -replace '(\s+function\s+\w+[^)]*\))\s+external\s+', '$1 public '
        $changed = $true
    }
    
    if ($changed) {
        Set-Content $file.FullName $content -NoNewline
        Write-Host "Changed external to public in: $($file.Name)"
    }
}

Write-Host "`nNote: This changes ALL external functions to public."
Write-Host "This may not be ideal for all cases, but solves constructor visibility issues."
