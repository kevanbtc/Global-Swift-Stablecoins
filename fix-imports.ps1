# Fix incorrect file imports based on actual directory structure

$contractsPath = "contracts"

# Map of incorrect imports to correct ones
$importFixes = @{
    'import "\./AIAgentRegistry\.sol"' = 'import "../ai/AIAgentRegistry.sol"'
}

Get-ChildItem -Path $contractsPath -Recurse -Filter *.sol | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $modified = $false
    
    # Fix AIAgentRegistry imports in subdirectories
    if ($_.Directory.Name -ne "contracts" -and $_.Directory.Name -ne "ai") {
        if ($content -match 'import "\./AIAgentRegistry\.sol"') {
            $content = $content -replace 'import "\./AIAgentRegistry\.sol"', 'import "../ai/AIAgentRegistry.sol"'
            $modified = $true
        }
    }
    
    if ($modified) {
        Set-Content -Path $_.FullName -Value $content -NoNewline
        Write-Host "Fixed: $($_.FullName)"
    }
}

Write-Host "`nImport fixes completed!"
