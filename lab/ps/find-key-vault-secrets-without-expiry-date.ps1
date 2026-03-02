# ============================================================
# Script: Find Key Vault Secrets Without Expiry (Interactive)
# Description: Scans Azure Key Vaults for secrets missing expiration dates.
# Supports filtering by Subscription and Resource Group.
# ============================================================

# 1. Check for Active Connection
$subscriptions = Get-AzSubscription
if ($null -eq $subscriptions) {
    Write-Error "No subscriptions found. Please run 'Connect-AzAccount' first."
    return
}

# 2. Input Parameter: Subscription Filtering
$subChoice = Read-Host "Scan [A]ll subscriptions or [O]ne specific subscription? (Default: A)"
if ($subChoice -eq "O") {
    $targetSubId = Read-Host "Enter the Subscription ID"
    $subscriptions = $subscriptions | Where-Object { $_.Id -eq $targetSubId }
    if ($null -eq $subscriptions) { 
        Write-Host "Subscription ID not found!" -ForegroundColor Red; return 
    }
}

# 3. Input Parameter: Resource Group Filtering
$rgChoice = Read-Host "Scan [A]ll Resource Groups or [O]ne specific RG? (Default: A)"
$targetRG = $null
if ($rgChoice -eq "O") {
    $targetRG = Read-Host "Enter the Resource Group Name"
}

$results = [System.Collections.Generic.List[PSObject]]::new()

# 4. Main Execution Logic
foreach ($sub in $subscriptions) {
    Write-Host "`n>>> Processing Subscription: $($sub.Name)" -ForegroundColor Cyan
    $null = Set-AzContext -SubscriptionId $sub.Id -TenantId $sub.TenantId -Force

    try {
        # Fetch vaults based on RG filter
        if ($null -ne $targetRG) {
            $vaults = Get-AzKeyVault -ResourceGroupName $targetRG -ErrorAction SilentlyContinue
        } else {
            $vaults = Get-AzKeyVault -ErrorAction SilentlyContinue
        }

        if ($null -eq $vaults) { 
            Write-Host "  No Key Vaults found in the selected scope." -ForegroundColor Gray
            continue 
        }

        foreach ($vault in $vaults) {
            Write-Host "  Scanning Vault: $($vault.VaultName)" -ForegroundColor Gray
            
            try {
                # Get all secrets in the current vault
                $secrets = Get-AzKeyVaultSecret -VaultName $vault.VaultName -ErrorAction Stop
                
                foreach ($secret in $secrets) {
                    # Business Logic: Check for missing 'Expires' property
                    if ($null -eq $secret.Expires) {
                        Write-Host "    [!] No Expiry Found: $($secret.Name)" -ForegroundColor Yellow
                        
                        # Add metadata to our results list
                        $results.Add([PSCustomObject]@{
                            Subscription  = $sub.Name
                            ResourceGroup = $vault.ResourceGroupName
                            VaultName     = $vault.VaultName
                            SecretName    = $secret.Name
                            Enabled       = $secret.Enabled
                            Created       = $secret.Created
                        })
                    }
                }
            } catch {
                Write-Host "    [Access Denied/Error] on $($vault.VaultName)" -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Host "  Error accessing subscription $($sub.Name)" -ForegroundColor Red
    }
}

# 5. Export and Reporting
$exportPath = "$HOME/KeyVault_Report_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

if ($results.Count -gt 0) {
    # Ensure Downloads folder exists for Mac/Linux/Windows compatibility
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $exportPath)
    
    $results | Export-Csv -Path $exportPath -NoTypeInformation
    $results | Format-Table -AutoSize
    Write-Host "`nDone! Found $($results.Count) secrets. Report saved to: $exportPath" -ForegroundColor Green
} else {
    Write-Host "`nSuccess! No secrets found missing expiry dates in the selected scope." -ForegroundColor Green
}
