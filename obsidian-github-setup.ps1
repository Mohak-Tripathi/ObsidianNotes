# ============================================================
# Obsidian Vault → GitHub Setup Script
# Run this ONCE from PowerShell as normal user (no admin needed)
# ============================================================

$VAULT_CURRENT = "G:\My Drive\ObsidianVault\ObsidianNotes"
$VAULT_LOCAL   = "C:\Users\mohak\ObsidianVault\ObsidianNotes"
$REMOTE        = "git@github.com:Mohak-Tripathi/ObsidianNotes.git"

# ── STEP 1: Init git and push from current Google Drive location ──────────────
Write-Host "`n[1/4] Initialising git in vault..." -ForegroundColor Cyan
Set-Location $VAULT_CURRENT
git init
git add .
git commit -m "init: vault backup $(Get-Date -Format 'yyyy-MM-dd')"
git branch -M main
git remote add origin $REMOTE
git push -u origin main

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] Push failed. Check your SSH key is added to GitHub (ssh -T git@github.com)." -ForegroundColor Red
    exit 1
}

Write-Host "`n[1/4] Done — vault pushed to GitHub." -ForegroundColor Green

# ── STEP 2: Move vault from Google Drive to local path ────────────────────────
Write-Host "`n[2/4] Moving vault to local path..." -ForegroundColor Cyan
$parent = Split-Path $VAULT_LOCAL
if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
Move-Item -Path $VAULT_CURRENT -Destination $VAULT_LOCAL
Write-Host "[2/4] Done — vault is now at $VAULT_LOCAL" -ForegroundColor Green

# ── STEP 3: Verify git remote still intact ────────────────────────────────────
Write-Host "`n[3/4] Verifying git remote from new location..." -ForegroundColor Cyan
Set-Location $VAULT_LOCAL
git remote -v
Write-Host "[3/4] Done." -ForegroundColor Green

# ── STEP 4: Instructions ──────────────────────────────────────────────────────
Write-Host "`n[4/4] MANUAL STEPS LEFT:" -ForegroundColor Yellow
Write-Host "  1. Open Obsidian → Manage vaults → Open folder as vault"
Write-Host "     → select: $VAULT_LOCAL"
Write-Host "  2. Delete the old empty folder from Google Drive if it remains"
Write-Host "  3. Install Obsidian Git plugin (Settings → Community plugins → Browse → 'Obsidian Git')"
Write-Host ""
Write-Host "All done. Your vault is now local + synced to GitHub." -ForegroundColor Green
