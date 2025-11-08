# Rename Errors library to CustomErrors to avoid conflict with OpenZeppelin v5

$files = Get-ChildItem "contracts" -Recurse -Filter "*.sol"

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $changed = $false
    
    # Replace revert Errors. with revert CustomErrors.
    if ($content -match "revert Errors\.") {
        $content = $content -replace "revert Errors\.", "revert CustomErrors."
        $changed = $true
    }
    
    if ($changed) {
        Set-Content $file.FullName $content -NoNewline
        Write-Host "Updated: $($file.FullName)"
    }
}
