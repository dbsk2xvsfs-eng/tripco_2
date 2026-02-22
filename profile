function build {
  param(
    [ValidateSet("apk","appbundle","run","debug")]
    [string]$target = "apk"
  )
  powershell -ExecutionPolicy Bypass -File "$PWD\build_backup.ps1" -target $target
}
