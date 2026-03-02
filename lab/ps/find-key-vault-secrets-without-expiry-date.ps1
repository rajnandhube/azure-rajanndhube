# ============================================================
# Script: Find Key Vault Secrets (Interactive Number Selection)
# ============================================================

# 1. Get and List Subscriptions
$allSubs = Get-AzSubscription | Sort-Object Name
if ($null -eq $allSubs) {
    Write-Error "No subscriptions found. Run 'Connect-AzAccount' first."
    return
}

Write-Host "`n--- Available Subscriptions ---" -ForegroundColor Cyan
Write-Host "[0] Scan All Subscriptions"
for ($i = 0; $i -lt $allSubs.Count; $i++) {
    Write-Host "[$($i + 1)] $($allSubs[$i].Name) ($($allSubs[$i].Id))"
}

# 2. Input Parameter: Subscription Selection
$subInput = Read-Host "`nEnter selection number (Default: 0)"
$selectedSubs = $allSubs
$index = 0 # Initialize to avoid [ref] error

if (-not [string]::IsNullOrWhiteSpace($subInput) -and $subInput -ne "0") {
    if ([int]::TryParse($subInput, [ref]$index)) {
        $index-- # Convert 1-based user input to 0-based array index
        if ($index -ge 0 -and $index -lt $allSubs.Count) {
            $selectedSubs = @($allSubs[$index])
        } else {
            Write-Host "Invalid selection. Defaulting to All Subscriptions." -ForegroundColor Yellow
        }
    }
}

# 3. Input Parameter: Resource Group Selection
$targetRG = $null
$rgIndex = 0 

# Only offer RG selection if exactly ONE subscription is chosen
if ($selectedSubs.Count -eq 1) {
    Write-Host "`nFetching Resource Groups for $($selectedSubs[0].Name)..." -ForegroundColor Gray
    $null = Set-AzContext -SubscriptionId $selectedSubs[0].Id -TenantId $selectedSubs[0].TenantId -Force
    $allRGs = Get-AzResourceGroup | Sort-Object ResourceGroupName
    
    if ($allRGs.Count -gt 0) {
        Write-Host "`n--- Available Resource Groups ---" -ForegroundColor Cyan
        Write-Host "[0] Scan All Resource Groups"
        for ($j = 0; $j -lt $allRGs.Count; $j++) {
            Write-Host "[$($j + 1)] $($allRGs[$j].ResourceGroupName)"
        }

        $rgInput = Read-Host "`nEnter selection number (Default: 0)"
        if (-not [string]::IsNullOrWhiteSpace($rgInput) -and $rgInput -ne "0") {
            if ([int]::TryParse($rgInput, [ref]$rgIndex)) {
                $rgIndex--
                if ($rgIndex -ge 0 -and $rgIndex -lt $allRGs.Count) {
                    $targetRG = $allRGs[$rgIndex].ResourceGroupName
                }
            }
        }
    }
} else {
    Write-Host "`nScanning All Resource Groups across all selected subscriptions..." -ForegroundColor Gray
}

$results = [System.Collections.Generic.List[PSObject]]::new()

# 4. Main Execution Logic
foreach ($sub in $selectedSubs) {
    $subDisplay = "$($sub.Name) ($($sub.Id))"
    Write-Host "`n>>> Processing: $subDisplay" -ForegroundColor Cyan
    
    # Set context to current sub to prevent cross-subscription errors
    $null = Set-AzContext -SubscriptionId $sub.Id -TenantId $sub.TenantId -Force

    try {
        # Fetch vaults based on target RG or all
        if ($null -ne $targetRG) {
            $vaults = Get-AzKeyVault -ResourceGroupName $targetRG -ErrorAction SilentlyContinue
        } else {
            $vaults = Get-AzKeyVault -ErrorAction SilentlyContinue
        }

        if ($null -eq $vaults) { continue }

        foreach ($vault in $vaults) {
            Write-Host "  Scanning Vault: $($vault.VaultName)" -ForegroundColor Gray
            
            try {
                # Get secret metadata
                $secrets = Get-AzKeyVaultSecret -VaultName $vault.VaultName -ErrorAction Stop
                
                foreach ($secret in $secrets) {
                    $hasExpiry = if ($null -ne $secret.Expires) { "Yes" } else { "No" }
                    
                    # Core Logic: Filter for missing expiry dates
                    if ($hasExpiry -eq "No") {
                        
                        # Flatten Tags into a single CSV cell (Format Key:Value; Key:Value)
                        $tagString = ""
                        if ($null -ne $secret.Tags) {
                            $tagString = ($secret.Tags.GetEnumerator() | ForEach-Object { "$($_.Key):$($_.Value)" }) -join "; "
                        }

                        $results.Add([PSCustomObject]@{
                            SecretName     = $secret.Name
                            VaultName      = $vault.VaultName
                            HasExpiry      = $hasExpiry
                            Tags           = $tagString
                            Enabled        = $secret.Enabled
                            Created        = $secret.Created
                            ResourceGroup  = $vault.ResourceGroupName
                            Subscription   = $subDisplay
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

# 5. Export results to CSV
$exportPath = "$HOME/KeyVault_Expiry_Report_$(Get-Date -Format 'yyyyMMdd_HHmm').csv"

if ($results.Count -gt 0) {
    $results | Export-Csv -Path $exportPath -NoTypeInformation
    $results | Format-Table -AutoSize
    Write-Host "`nDone! Found $($results.Count) items. Saved to: $exportPath" -ForegroundColor Green
} else {
    Write-Host "`nNo secrets found missing expiry dates." -ForegroundColor Green
}
