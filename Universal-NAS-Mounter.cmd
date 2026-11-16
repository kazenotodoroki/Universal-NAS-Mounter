@echo off
rem Universal NAS Mounter - maps a network share (NAS) as a Windows drive. Double-click to run.
set "SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((Get-Content -Raw -LiteralPath $env:SELF) -split ':PS1\r?\n',2)[1]"
exit /b
:PS1
$Host.UI.RawUI.WindowTitle = 'Universal NAS Mounter'
function Pause-Exit { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null; exit }
function Clean($o, $secret) {
  $t = ($o | ForEach-Object { "$_" } | Where-Object { $_ -and $_ -notmatch 'RemoteException' }) -join ' '
  if ($secret) { $t = $t -replace [regex]::Escape($secret), '***' }
  $t.Trim()
}

function Read-Secret($prompt) {
  Write-Host "${prompt}: " -NoNewline
  while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
  $s = ''
  while ($true) {
    $k = [Console]::ReadKey($true)
    if ($k.Key -eq 'Enter') { break }
    if ($k.Key -eq 'Backspace') {
      if ($s.Length) { $s = $s.Substring(0, $s.Length - 1); Write-Host "`b `b" -NoNewline }
      continue
    }
    if ($k.KeyChar -eq [char]0 -or [char]::IsControl($k.KeyChar)) { continue }
    $s += $k.KeyChar
    Write-Host '*' -NoNewline
  }
  Write-Host ''
  $s
}

Write-Host '=== Universal NAS Mounter - map a NAS share as a network drive ===' -ForegroundColor Cyan
Write-Host ''

# 1. NAS address
do { $ip = (Read-Host 'NAS IP address (or hostname)').Trim().Trim('\') } while (-not $ip)

Write-Host "Testing connection to $ip (port 445, 5 seconds max)..."
$ok = $false
try {
  $c = New-Object Net.Sockets.TcpClient
  $ar = $c.BeginConnect($ip, 445, $null, $null)
  $ok = $ar.AsyncWaitHandle.WaitOne(5000) -and $c.Connected
  $c.Close()
} catch { $ok = $false }
if (-not $ok) {
  Write-Host "The NAS is not responding on the SMB port (445)." -ForegroundColor Red
  Write-Host "Check the address, that the NAS is powered on, that your VPN (NetBird...) is connected,"
  Write-Host "and that the firewall / access rule allows TCP port 445."
  Pause-Exit
}
Write-Host "  OK, the NAS is responding." -ForegroundColor Green
Write-Host ''

# 2. Credentials (3 attempts)
net use "\\$ip\IPC$" /delete /y 2>&1 | Out-Null
$user = $null
for ($try = 1; $try -le 3 -and -not $user; $try++) {
  do { $id = (Read-Host 'Username').Trim() } while (-not $id)
  $pw = Read-Secret 'Password (hidden, press Enter to confirm)'
  $last = ''
  foreach ($u in @($id, $id.ToLower()) | Select-Object -Unique) {
    $out = net use "\\$ip\IPC$" $pw /user:$u 2>&1
    if ($LASTEXITCODE -eq 0) { $user = $u; break }
    $last = Clean $out $pw
  }
  if (-not $user) {
    Write-Host "  Rejected: $last" -ForegroundColor Yellow
    if ($last -match '1219') {
      Write-Host "  A connection to this NAS already exists with a different username."
      Write-Host "  Disconnect the drives mapped to this NAS (or restart) and run the script again."
      Pause-Exit
    }
    if ($last -match '1326') { Write-Host "  Wrong username or password (note: the network/SMB password may differ from the web interface password)." }
    Write-Host ''
  }
}
if (-not $user) { Write-Host 'Failed after 3 attempts.' -ForegroundColor Red; Pause-Exit }
Write-Host "  OK, credentials accepted (user $user)." -ForegroundColor Green
Write-Host ''

# 3. Share selection
Write-Host 'Shares available on this NAS:'
$view = net view "\\$ip" 2>&1
$shares = @()
foreach ($l in $view) { if ("$l" -match '^(.+?)\s{2,}(Disque|Disk)\b') { $shares += $Matches[1].Trim() } }
if ($shares.Count) { for ($i = 0; $i -lt $shares.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $shares[$i]) } }
else { Write-Host '  (list unavailable, type the share name)' }
do {
  $s = (Read-Host 'Share to map (number or name)').Trim().Trim('\')
  if ($s -match '^\d+$' -and [int]$s -ge 1 -and [int]$s -le $shares.Count) { $s = $shares[[int]$s - 1] }
} while (-not $s)
$unc = "\\$ip\$s"
Write-Host ''

# 4. Drive letter
$used = @((Get-PSDrive -PSProvider FileSystem).Name) + @(Get-CimInstance Win32_LogicalDisk | ForEach-Object { $_.DeviceID.TrimEnd(':') })
$free = [char[]](90..68) | ForEach-Object { "$_" } | Where-Object { $used -notcontains $_ }
$def = $free | Select-Object -First 1
$letter = $null
while (-not $letter) {
  $l = (Read-Host "Drive letter [$def]").Trim().TrimEnd(':').ToUpper()
  if (-not $l) { $l = $def }
  if ($l -notmatch '^[A-Z]$') { Write-Host '  Type a single letter (e.g. Z).' -ForegroundColor Yellow; continue }
  if ($used -contains $l) {
    $r = Read-Host "  Drive ${l}: is already in use. Replace it? (y/N)"
    if ($r -notmatch '^[oOyY]') { continue }
    $o = net use "${l}:" /delete /y 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Host "  Cannot free ${l}: (it may not be a network drive)." -ForegroundColor Yellow; continue }
  }
  $letter = "${l}:"
}

# 5. Remember?
$r = Read-Host 'Reconnect automatically at sign-in and remember the password on this PC? (Y/n)'
$keep = $r -notmatch '^[nN]'
Write-Host ''

# 6. Mapping
if ($keep) {
  cmdkey /add:$ip /user:$user /pass:$pw | Out-Null
  $out = net use $letter $unc /persistent:yes 2>&1
} else {
  $out = net use $letter $unc $pw /user:$user /persistent:no 2>&1
}
if ($LASTEXITCODE -eq 0) {
  Write-Host "Done: $unc is mapped to $letter" -ForegroundColor Green
  if ($keep) { Write-Host 'It will reconnect at every sign-in (credentials stored in Windows Credential Manager).' }
  Start-Process explorer.exe $letter
} else {
  Write-Host ("Mapping failed: " + (Clean $out $pw)) -ForegroundColor Red
  if ($keep) { cmdkey /delete:$ip | Out-Null }
}
$pw = $null
Pause-Exit
