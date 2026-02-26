# ============================================================
# Script: Find Key Vault Secrets Without Expiry (Mac/All-Subs)
# ============================================================

# Get ALL subscriptions across all tenants you just logged into
$subscriptions = Get-AzSubscription

if ($null -eq $subscriptions) {
    Write-Error "No subscriptions found. Run 'Connect-AzAccount' manually first."
    return
}

$results = [System.Collections.Generic.List[PSObject]]::new()

foreach ($sub in $subscriptions) {
    Write-Host "`n>>> Processing: $($sub.Name) ($($sub.Id))" -ForegroundColor Cyan
    
    # Set context for this specific sub/tenant to avoid prompts
    $null = Set-AzContext -SubscriptionId $sub.Id -TenantId $sub.TenantId -Force

    try {
        $vaults = Get-AzKeyVault -ErrorAction SilentlyContinue
        if ($null -eq $vaults) { continue }

        foreach ($vault in $vaults) {
            Write-Host "  Scanning Vault: $($vault.VaultName)" -ForegroundColor Gray
            
            try {
                # Get all secrets in this vault
                $secrets = Get-AzKeyVaultSecret -VaultName $vault.VaultName -ErrorAction Stop
                
                foreach ($secret in $secrets) {
                    # Identify secrets missing an expiry date
                    if ($null -eq $secret.Expires) {
                        Write-Host "    [!] No Expiry: $($secret.Name)" -ForegroundColor Yellow
                        
                        $results.Add([PSCustomObject]@{
                            Subscription = $sub.Name
                            VaultName    = $vault.VaultName
                            SecretName   = $secret.Name
                            Enabled      = $secret.Enabled
                            Created      = $secret.Created
                        })
                    }
                }
            } catch {
                Write-Host "    [Access Denied] on $($vault.VaultName)" -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Host "  Error accessing subscription $($sub.Name)" -ForegroundColor Red
    }
}

# ============================================================
# Display & Export to Mac Downloads
# ============================================================
$exportPath = "$HOME/Downloads/KeyVault_Report_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

if ($results.Count -gt 0) {
    $results | Export-Csv -Path $exportPath -NoTypeInformation
    $results | Format-Table -AutoSize
    Write-Host "`nDone! Found $($results.Count) secrets. Report saved to: $exportPath" -ForegroundColor Green
} else {
    Write-Host "`nSuccess! No secrets found missing expiry dates." -ForegroundColor Green
}
