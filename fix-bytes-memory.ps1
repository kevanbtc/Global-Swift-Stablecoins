# Fix type(bytes).memory syntax errors

$file = "contracts\infrastructure\UniversalDeployer.sol"
$content = Get-Content $file -Raw

# Replace all occurrences of type(bytes).memory with new bytes(0)
$content = $content -replace 'type\(bytes\)\.memory', 'new bytes(0)'

Set-Content $file $content -NoNewline
Write-Host "Fixed type(bytes).memory in: $file"
