# Remove SafeMath from contracts (no longer needed in Solidity 0.8+)

$files = Get-ChildItem "contracts" -Recurse -Filter "*.sol" | Where-Object { 
    $content = Get-Content $_.FullName -Raw
    $content -match "SafeMath"
}

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    
    # Remove SafeMath import
    $content = $content -replace 'import "@openzeppelin/contracts/utils/math/SafeMath\.sol";\r?\n', ''
    
    # Remove using SafeMath directive
    $content = $content -replace '\s*using SafeMath for uint256;\r?\n', ''
    
    Set-Content $file.FullName $content -NoNewline
    Write-Host "Removed SafeMath from: $($file.FullName)"
}
