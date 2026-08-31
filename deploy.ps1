# Deploy holaperros.pl -> CyberFolks (WinSCP, FTP)
# Wzorowane na webstudio47/deploy.ps1.
# Haslo pobierane W LOCIE z zapisanej sesji FileZilli (ntroixgelh@s75) - brak sekretow w repo.
#
# Uzycie:
#   npm run build:deploy                                          # build + PRERENDER
#   powershell -ExecutionPolicy Bypass -File deploy.ps1 -Lista    # pokaz, co poleci
#   powershell -ExecutionPolicy Bypass -File deploy.ps1           # wysylka
#
# WAZNE: wysylaj po `build:deploy`, nie po samym `build`. Bez prerenderu
# bot bez JavaScriptu dostaje pusty <div id="root"> i zero znakow tresci -
# a wtedy GPTBot, PerplexityBot i podglad linku na Facebooku nie maja
# czego pokazac. Skrypt to sprawdza i przerywa, jesli tresci brak.
#
# Wysylamy zawartosc dist/ przez `put`, NIE `synchronize`: na serwerze moga
# lezec pliki wgrane recznie, o ktorych repo nie wie, a synchronizacja
# by je skasowala.

param(
  [switch]$Lista,
  [string]$Remote = '/domains/holaperros.pl/public_html'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$Dist = "$PSScriptRoot\dist"

# --- Kontrola przed wysylka --------------------------------------------------

if (-not (Test-Path "$Dist\index.html")) { throw 'Brak dist/index.html - najpierw: npm run build:deploy' }
if (-not (Test-Path "$Dist\.htaccess"))  { throw "Brak dist/.htaccess" }

# Straznik prerenderu: index.html po samym `vite build` ma pusty root
# i wazy ok. 3 KB. Po prerenderze - ponad 90 KB pelnej tresci.
$html = Get-Content "$Dist\index.html" -Raw
if ($html -match '<div id="root"></div>') {
  throw 'dist/index.html ma PUSTY root - prerender nie zostal uruchomiony. ' +
        'Uruchom: npm run build:deploy (nie samo npm run build).'
}
if ($html -notmatch '<h1') {
  throw 'dist/index.html nie ma <h1> - prerender sie nie udal. Sprawdz: npm run prerender'
}

$tekst = ($html -replace '(?s)<(script|style)[^>]*>.*?</\1>', ' ') -replace '<[^>]+>', ' '
$tekst = ($tekst -replace '\s+', ' ').Trim()
if ($tekst.Length -lt 2000) {
  throw "dist/index.html ma tylko $($tekst.Length) znakow tresci - prerender niekompletny."
}

# /panel to administracja, /bio duplikuje strone glowna - oba musza miec noindex
foreach ($n in @('panel', 'bio')) {
  $f = "$Dist\$n\index.html"
  if ((Test-Path $f) -and ((Get-Content $f -Raw) -notmatch 'noindex')) {
    throw "$n/index.html bez noindex - trafi do Google. Dodaj znacznik i przebuduj."
  }
}

if ($Lista) {
  Write-Host "Poleci zawartosc dist/ -> $Remote" -ForegroundColor Cyan
  Get-ChildItem $Dist -Force | ForEach-Object {
    if ($_.PSIsContainer) {
      $n = (Get-ChildItem $_.FullName -Recurse -File).Count
      "  $($_.Name)\  ($n plikow)"
    } else {
      $kb = [math]::Round($_.Length / 1KB)
      "  $($_.Name)  ($kb KB)"
    }
  }
  Write-Host ""
  Write-Host "Tresc w index.html: $($tekst.Length) znakow (prerender OK)" -ForegroundColor Green
  return
}

# --- Haslo z zapisanej sesji FileZilli ---------------------------------------

[xml]$r = Get-Content "$env:APPDATA\FileZilla\recentservers.xml"
$s = @($r.FileZilla3.RecentServers.Server | Where-Object {
  $_.Host -eq 's75.cyber-folks.pl' -and $_.User -eq 'ntroixgelh' -and $_.Pass.'#text'
})[0]
if (-not $s) { throw "Brak zapisanej sesji ntroixgelh@s75 w FileZilli" }
$pass  = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s.Pass.'#text'))
$passQ = $pass -replace '"','""'

# --- Skrypt dla WinSCP -------------------------------------------------------

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('option batch abort')
$lines.Add('option confirm off')
$lines.Add('open ftp://ntroixgelh@s75.cyber-folks.pl:21 -passive=on -password="' + $passQ + '"')
$lines.Add('cd "' + $Remote + '"')
# Gwiazdka wysyla ZAWARTOSC dist, a nie sam katalog dist. Bez niej
# powstalby /public_html/dist i strona zostalaby stara.
$lines.Add('put "' + $Dist + '\*" "' + $Remote + '/"')
$lines.Add('exit')

Write-Host ">> Wysylka dist/ -> $Remote ..." -ForegroundColor Cyan

$tmp = "$env:TEMP\ws_holaperros.txt"
Set-Content $tmp $lines -Encoding ascii
$log = "$env:TEMP\ws_holaperros_out.txt"
cmd /c "`"C:\Program Files (x86)\WinSCP\WinSCP.com`" /script=`"$tmp`" /ini=nul > `"$log`" 2>&1"
$kod = $LASTEXITCODE
Get-Content $log | Select-Object -Last 25
Remove-Item $tmp, $log -Force
if ($kod -ne 0) { throw "WinSCP zakonczyl z kodem $kod" }

Write-Host ""
Write-Host ">> OK - https://holaperros.pl zaktualizowane." -ForegroundColor Green
Write-Host "   Sprawdz: python ~/.claude/skills/robienie-stron/sprawdz.py --url holaperros.pl"
