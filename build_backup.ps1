param(
  [ValidateSet('apk','appbundle','run','debug')]
  [string]$target = 'apk'
)

function Fail($msg) {
  Write-Host $msg -ForegroundColor Red
  exit 1
}

if (!(Test-Path .\pubspec.yaml)) {
  Fail 'Nenalezen pubspec.yaml. Spust to v koreni Flutter projektu.'
}

Write-Host ('== Flutter ' + $target + ' ==') -ForegroundColor Cyan

if ($target -eq 'apk') {
  flutter build apk
} elseif ($target -eq 'appbundle') {
  flutter build appbundle
} elseif ($target -eq 'debug') {
  flutter build apk --debug
} elseif ($target -eq 'run') {
  flutter run
}

if ($LASTEXITCODE -ne 0) {
  Fail 'Build selhal – zalohu neprovadim.'
}

$changes = git status --porcelain
if ([string]::IsNullOrWhiteSpace($changes)) {
  Write-Host '== Zadne zmeny k zaloze ==' -ForegroundColor Yellow
  exit 0
}

$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$msg = 'Auto backup after build: ' + $ts

git add -A
git commit -m $msg
if ($LASTEXITCODE -ne 0) {
  Fail 'Commit selhal.'
}

git push
if ($LASTEXITCODE -ne 0) {
  Fail 'Push selhal.'
}

Write-Host '== Hotovo: zaloha odeslana na GitHub ==' -ForegroundColor Green
