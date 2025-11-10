# Fix import statements for renamed CustomErrors library

$files = @(
    "contracts\token\InstitutionalEMTUpgradeable.sol",
    "contracts\compliance\AccessRegistryUpgradeable.sol",
    "contracts\ccip\PorBroadcaster.sol",
    "contracts\mica\ReserveManagerUpgradeable.sol",
    "contracts\compliance\PolicyEngineUpgradeable.sol"
)

foreach ($file in $files) {
    $content = Get-Content $file -Raw
    $content = $content -replace 'import \{Errors\} from "(.*)Errors\.sol";', 'import {CustomErrors} from "$1Errors.sol";'
    Set-Content $file $content -NoNewline
    Write-Host "Updated import in: $file"
}
