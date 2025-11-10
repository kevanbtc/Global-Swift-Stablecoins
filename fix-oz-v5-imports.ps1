# Fix OpenZeppelin v5 import paths
# In v5, security/ directory was removed and modules moved to utils/

$contractsPath = "contracts"

# Fix security/ReentrancyGuard -> utils/ReentrancyGuard
Get-ChildItem -Path $contractsPath -Recurse -Filter *.sol | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $modified = $false
    
    # Fix non-upgradeable ReentrancyGuard
    if ($content -match '@openzeppelin/contracts/security/ReentrancyGuard') {
        $content = $content -replace '@openzeppelin/contracts/security/ReentrancyGuard', '@openzeppelin/contracts/utils/ReentrancyGuard'
        $modified = $true
    }
    
    # Fix upgradeable ReentrancyGuard
    if ($content -match '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable') {
        $content = $content -replace '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable', '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable'
        $modified = $true
    }
    
    # Fix Pausable
    if ($content -match '@openzeppelin/contracts/security/Pausable') {
        $content = $content -replace '@openzeppelin/contracts/security/Pausable', '@openzeppelin/contracts/utils/Pausable'
        $modified = $true
    }
    
    # Fix upgradeable Pausable
    if ($content -match '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable') {
        $content = $content -replace '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable', '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable'
        $modified = $true
    }
    
    # Fix ../common/ imports in root contracts directory
    if ($_.Directory.Name -eq "contracts" -and $content -match '\.\./common/') {
        $content = $content -replace '\.\./common/', './common/'
        $modified = $true
    }
    
    if ($modified) {
        Set-Content -Path $_.FullName -Value $content -NoNewline
        Write-Host "Fixed: $($_.FullName)"
    }
}

Write-Host "`nImport path fixes completed!"
