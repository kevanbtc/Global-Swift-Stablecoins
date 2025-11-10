# Fix lib/openzeppelin imports to use @openzeppelin packages
# This fixes Foundry-style imports to Hardhat-style imports

$files = @(
    "contracts\fees\ContractAccessFee.sol",
    "contracts\settlement\SrCompliantDvP.sol",
    "contracts\nft\DeploymentProofNFT.sol"
)

foreach ($file in $files) {
    $content = Get-Content $file -Raw
    
    # Fix regular OpenZeppelin contracts
    $content = $content -replace 'lib/openzeppelin-contracts/contracts/', '@openzeppelin/contracts/'
    
    # Fix upgradeable OpenZeppelin contracts  
    $content = $content -replace 'lib/openzeppelin-contracts-upgradeable/contracts/', '@openzeppelin/contracts-upgradeable/'
    
    # Also fix security/ to utils/ for v5 in case any upgradeable ones have it
    $content = $content -replace '@openzeppelin/contracts-upgradeable/security/', '@openzeppelin/contracts-upgradeable/utils/'
    $content = $content -replace '@openzeppelin/contracts/security/', '@openzeppelin/contracts/utils/'
    
    Set-Content $file $content -NoNewline
    Write-Host "Fixed: $file"
}
