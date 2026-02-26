# ============================================================
# Script: Find Key Vault Secrets Without Expiry Date
# Scope : All Subscriptions & All Key Vaults
# ============================================================

# Connect to Azure
Connect-AzAccount

# Output collection
$results = @()

# Get all subscriptions
$subscriptions = Get-AzSubscription

foreach ($sub in $subscriptions) {
    Write-Host "`nProcessing Subscription: $($sub.Name) [$($sub.Id)]" -ForegroundColor Cyan

    # Set context to current subscription
    Set-AzContext -SubscriptionId $sub.Id | Out-Null

    # Get all Key Vaults in the subscription
    $vaults = Get-AzKeyVault

    if ($vaults.Count -eq 0) {
        Write-Host "  No Key Vaults found in this subscription." -ForegroundColor Yellow
        continue
    }

    foreach ($vault in $vaults) {
        Write-Host "  Scanning Vault: $($vault.VaultName)" -ForegroundColor Green

        try {
            $secrets = Get-AzKeyVaultSecret -VaultName $vault.VaultName -ErrorAction Stop

            foreach ($secret in $secrets) {
                try {
                    $detail = Get-AzKeyVaultSecret -VaultName $vault.VaultName -Name $secret.Name -ErrorAction Stop

                    if ($null -eq $detail.Expires) {
                        Write-Host "    [NO EXPIRY] Secret: $($secret.Name)" -ForegroundColor Red

                        $results += [PSCustomObject]@{
                            SubscriptionName = $sub.Name
                            SubscriptionId   = $sub.Id
                            KeyVaultName     = $vault.VaultName
                            ResourceGroup    = $vault.ResourceGroupName
                            SecretName       = $secret.Name
                            Enabled          = $detail.Enabled
                            CreatedOn        = $detail.Created
                            UpdatedOn        = $detail.Updated
                            ExpiryDate       = "NOT SET"
                        }
                    }
                } catch {
                    Write-Host "    [ERROR] Could not retrieve secret '$($secret.Name)': $_" -ForegroundColor Magenta
                }
            }
        } catch {
            Write-Host "  [ACCESS DENIED or ERROR] Vault: $($vault.VaultName) - $_" -ForegroundColor Magenta
        }
    }
}

# ============================================================
# Display Results in Table
# ============================================================
Write-Host "`n===== SECRETS WITHOUT EXPIRY DATE =====" -ForegroundColor Yellow
$results | Format-Table -AutoSize

# ============================================================
# Export to CSV
# ============================================================
$exportPath = "C:\Temp\KeyVault_Secrets_NoExpiry_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $exportPath -NoTypeInformation
Write-Host "`nReport exported to: $exportPath" -ForegroundColor Green

# ============================================================
# Summary
# ============================================================
Write-Host "`n===== SUMMARY =====" -ForegroundColor Cyan
Write-Host "Total Subscriptions Scanned : $($subscriptions.Count)"
Write-Host "Total Secrets Without Expiry: $($results.Count)" -ForegroundColor Red
