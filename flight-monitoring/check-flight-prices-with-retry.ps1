# Flight Price Check Wrapper with Retry Logic
# Attempts the flight check, waits 1 minute and retries once on failure

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $ScriptDir 'check-flight-prices.ps1'

Write-Host "Starting flight check (with retry logic)..."

# First attempt
try {
    $result = & $scriptPath 2>&1
    $exitCode = $LASTEXITCODE
    
    # Check if it succeeded
    if ($exitCode -eq 0 -and $result -match "SUCCESS") {
        Write-Output $result
        exit 0
    } else {
        Write-Host "❌ First attempt failed or returned warnings"
        Write-Host "Exit code: $exitCode"
        Write-Host "Output: $result"
        throw "First attempt did not succeed"
    }
} catch {
    Write-Host "⏳ Waiting 60 seconds before retry..."
    Start-Sleep -Seconds 60
    
    Write-Host "🔄 Retrying flight check (attempt 2/2)..."
    
    try {
        $result = & $scriptPath 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0 -and $result -match "SUCCESS") {
            Write-Host "✅ Retry succeeded!"
            Write-Output $result
            exit 0
        } else {
            Write-Host "❌ Retry also failed"
            Write-Output "FAILURE: Both attempts failed. Exit code: $exitCode. Last output: $result"
            exit 1
        }
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Output "FAILURE: Both attempts failed. Retry error: $errorMsg"
        exit 1
    }
}
