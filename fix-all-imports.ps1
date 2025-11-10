# PowerShell script to fix all import path errors systematically
# Converts relative imports (../path) to absolute imports (./path)

Write-Host "=== Unykorn Import Path Fixer ===" -ForegroundColor Cyan
Write-Host "Fixing import paths across all contracts..." -ForegroundColor Yellow

$fixCount = 0
$errorCount = 0

# Get all Solidity files
$solidityFiles = Get-ChildItem -Path "contracts" -Filter "*.sol" -Recurse

foreach ($file in $solidityFiles) {
    try {
        $content = Get-Content $file.FullName -Raw
        $modified = $false
        
        # Fix common patterns
        $patterns = @{
            'import "\.\.\/common\/' = 'import "./common/'
            'import "\.\.\/interfaces\/' = 'import "./interfaces/'
            'import "\.\.\/\.\.\/common\/' = 'import "./common/'
            'import "\.\.\/\.\.\/interfaces\/' = 'import "./interfaces/'
            'import "\.\./AIAgentRegistry\.sol"' = 'import "./ai/AIAgentRegistry.sol"'
        }
        
        foreach ($pattern in $patterns.Keys) {
            if ($content -match $pattern) {
                $content = $content -replace $pattern, $patterns[$pattern]
                $modified = $true
            }
        }
        
        if ($modified) {
            Set-Content -Path $file.FullName -Value $content -NoNewline
            Write-Host "Fixed: $($file.FullName)" -ForegroundColor Green
            $fixCount++
        }
    }
    catch {
        Write-Host "Error processing $($file.FullName): $_" -ForegroundColor Red
        $errorCount++
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Files fixed: $fixCount" -ForegroundColor Green
Write-Host "Errors: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Green" })
Write-Host "`nNext: Run 'npm run compile' to verify" -ForegroundColor Yellow
