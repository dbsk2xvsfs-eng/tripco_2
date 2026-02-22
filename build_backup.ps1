# build_backup.ps1
# Spustí flutter build a po úspěchu udělá git commit + push (záloha)

param(
  [ValidateSet("apk","appbundle","run","debug")]
  [string]$target = "apk"
)

function Fail($msg) {
  Write-Host $msg -ForegroundColor Red
  exit 1
}

# 1) kontrola, že jsme ve Flutter projektu
if (!(Test-Path ".\pubspec.yaml")) {
  Fail "Nenalezen pubspec.yaml. Spusť to v kořeni Flutter projektu."
}

# 2) kontrola git
git rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) {
  Fail "Tohle není git repo. Nejprve: git init && git add . && git commit -m 'init'"
}

# 3) kontrola remote origin
$remote = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) {
  Fail "Chybí git remote 'origin'. Nejdřív přidej GitHub remote (git remote add origin ...)."
}

# 4) build / run
Write-Host "== Flutter $target ==" -ForegroundColor Cyan

if ($target -eq "apk") {
  flutter build apk
} elseif ($target -eq "appbundle") {
  flutter build appbundle
} elseif ($target -eq "debug") {
  flutter build apk --debug
} elseif ($target -eq "run") {
  flutter run
}

if ($LASTEXITCODE -ne 0) {
  Fail "Flutter build/run selhal. Záloha se neprovede (aby se nelogovaly rozbité změny)."
}

# 5) pokud není žádná změna, nic necommituj
git status --porcelain | Out-String | ForEach-Object { $changes = $_ }
if ([string]::IsNullOrWhiteSpace($changes)) {
  Write-Host "== Žádné změny k záloze ==" -ForegroundColor Yellow
  exit 0
}

# 6) commit + push
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$branch = (git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($branch)) { $branch = "main" }

Write-Host "== Git backup: commit + push ==" -ForegroundColor Green
git add -A
git commit -m "Auto backup after build: $ts"
if ($LASTEXITCODE -ne 0) {
  Fail "Commit selhal (možná chybí user.name/user.email)."
}

git push origin $branch
if ($LASTEXITCODE -ne 0) {
  Fail "Push selhal (zkontroluj přihlášení / token / rights)."
}

Write-Host "== Hotovo: záloha na GitHub ==" -ForegroundColor Green
