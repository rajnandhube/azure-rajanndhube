# ============================================================
# Script: Find Key Vault Secrets (Interactive Number Selection)
# ============================================================

# 1. Get and List Subscriptions
$allSubs = Get-AzSubscription
if ($null -eq $allSubs) {
    Write-Error "No subscriptions found. Run 'Connect-AzAccount' first."
    return
}

Write-Host "`n--- Available Subscriptions ---" -ForegroundColor Cyan
for ($i = 0; $i -lt $allSubs.Count; $i++) {
    Write-Host "[$($i + 1)] $($allSubs[$i].Name) ($($allSubs[$i].Id))"
}

# 2. Input Parameter: Subscription Selection
$subInput = Read-Host "`nEnter selection number or press Enter for [A]ll"
$selectedSubs = $allSubs

if (-not [string]::IsNullOrWhiteSpace($subInput)) {
    $index = [int]$subInput - 1
    if ($index -ge 0 -and $index -lt $allSubs.Count) {
        $selectedSubs = $allSubs[$index]
    } else {
        Write-Host "Invalid selection. Defaulting to All Subscriptions." -ForegroundColor Yellow
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
foreach ($sub in $selectedSubs) {
    # Format: Name (ID)
    $subDisplay = "$($sub.Name) ($($sub.Id))"
    Write-Host "`n>>> Processing: $subDisplay" -ForegroundColor Cyan
    $null = Set-AzContext -SubscriptionId $sub.Id -TenantId $sub.TenantId -Force

    try {
        if ($null -ne $targetRG) {
            $vaults = Get-AzKeyVault -ResourceGroupName $targetRG -ErrorAction SilentlyContinue
        } else {
            $vaults = Get-AzKeyVault -ErrorAction SilentlyContinue
        }

        foreach ($vault in $vaults) {
            Write-Host "  Scanning Vault: $($vault.VaultName)" -ForegroundColor Gray
            
            try {
                $secrets = Get-AzKeyVaultSecret -VaultName $vault.VaultName -ErrorAction Stop
                
                foreach ($secret in $secrets) {
                    # Determine if Expiry is set (Yes/No)
                    $hasExpiry = if ($null -ne $secret.Expires) { "Yes" } else { "No" }
                    
                    # Logic: If you only want secrets WITHOUT expiry, keep this filter:
                    if ($hasExpiry -eq "No") {
                        
                        # Convert Tags dictionary to a readable string (Key:Value; Key:Value)
                        $tagString = ""
                        if ($null -ne $secret.Tags) {
                            $tagString = ($secret.Tags.GetEnumerator() | ForEach-Object { "$($_.Key):$($_.Value)" }) -join "; "
                        }

                        $results.Add([PSCustomObject]@{
                            Subscription   = $subDisplay
                            ResourceGroup  = $vault.ResourceGroupName
                            VaultName      = $vault.VaultName
                            SecretName     = $secret.Name
                            HasExpiry      = $hasExpiry
                            Tags           = $tagString
                            Enabled        = $secret.Enabled
                            Created        = $secret.Created
                        })
                    }
                }
            } catch {
                Write-Host "    [Access Denied] on $($vault.VaultName)" -ForegroundColor DarkGray
            }
        }
    } catch {
        Write-Host "  Error in subscription $($sub.Name)" -ForegroundColor Red
    }
}

# 5. Export
$exportPath = "$HOME/Downloads/KeyVault_Expiry_Report_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

if ($results.Count -gt 0) {
    $results | Export-Csv -Path $exportPath -NoTypeInformation
    $results | Format-Table -AutoSize
    Write-Host "`nDone! Found $($results.Count) items. Saved to: $exportPath" -ForegroundColor Green
} else {
    Write-Host "`nNo secrets found missing expiry dates." -ForegroundColor Green
}
