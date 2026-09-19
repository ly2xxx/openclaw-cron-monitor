# Generic LinkedIn job search scanner using CDP and [data-job-id] selectors.
# Walks up to 3 pages and writes JSON files: <PAGE_PREFIX>1.json, 2.json, 3.json
#
# Environment variables (override defaults):
#   BASE_URL        - LinkedIn search URL (required, must include any f_TPR/keywords/location)
#   PAGE_PREFIX     - output file prefix (default: "linkedin-page" -> linkedin-page1.json etc.)
#   OUT_DIR         - output directory (default: script directory)
#   CHROME_DEBUG    - Chrome debug URL (default: http://localhost:9222)
#   ORIGIN_HEADER   - Origin header for WS (default: $CHROME_DEBUG value)

$ErrorActionPreference = 'Stop'

$ChromeDebug = if ($env:CHROME_DEBUG) { $env:CHROME_DEBUG } else { 'http://localhost:9222' }
$OriginHeader = if ($env:ORIGIN_HEADER) { $env:ORIGIN_HEADER } else { $ChromeDebug }
$OutDir = if ($env:OUT_DIR) { $env:OUT_DIR } elseif ($env:AI_JOB_MONITOR_DIR) { $env:AI_JOB_MONITOR_DIR } else { $PSScriptRoot }
$PagePrefix = if ($env:PAGE_PREFIX) { $env:PAGE_PREFIX } else { 'linkedin-page' }
$BaseURL = $env:BASE_URL
if (-not $BaseURL) {
  Write-Output "[ERR] BASE_URL env var is required"
  exit 1
}

# Ensure LinkedIn search URL ends with start param
if ($BaseURL -notmatch 'start=') {
  $BaseURL = "$BaseURL&start=0"
}

Write-Output "Scanning: $BaseURL"
Write-Output "Output prefix: $PagePrefix (dir: $OutDir)"

# ---- Find logged-in LinkedIn tab ----
$tabs = Invoke-RestMethod -Uri "$ChromeDebug/json" -Method Get
$tab = $tabs | Where-Object { $_.url -like '*linkedin.com/jobs/search*' } | Select-Object -First 1
if (-not $tab) {
  Write-Output "NO_LINKEDIN_TAB"
  exit 1
}
Write-Output "Tab: $($tab.id)"

# ---- Open WebSocket ----
$ws = [System.Net.WebSockets.ClientWebSocket]::new()
$ws.Options.SetRequestHeader('Origin', $OriginHeader)
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$tab.webSocketDebuggerUrl, $ct).Wait()

# ---- CDP helper ----
function Invoke-Cdp {
  param([string]$Method, [hashtable]$Params = @{})
  $id = Get-Random -Minimum 100000 -Maximum 999999
  $msg = @{ id = $id; method = $Method; params = $Params } | ConvertTo-Json -Compress -Depth 10
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
  $seg = [System.ArraySegment[byte]]::new($bytes)
  $ws.SendAsync($seg, 'Text', $true, $ct).Wait() | Out-Null
  $pattern = '"id":' + $id
  $buf = [byte[]]::new(262144)
  while ($true) {
    $rseg = [System.ArraySegment[byte]]::new($buf)
    $task = $ws.ReceiveAsync($rseg, $ct)
    $task.Wait()
    $data = $task.Result
    if ($data.Count -le 0) { break }
    $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $data.Count)
    if ($text.Contains($pattern)) { return $text }
  }
  return ''
}

# ---- Extract value ----
function Extract-Value {
  param([string]$Resp)
  $marker = '"value":"'
  $start = $Resp.IndexOf($marker)
  if ($start -lt 0) { return $null }
  $start += $marker.Length
  $payload = ''
  $i = $start
  while ($i -lt $Resp.Length) {
    $ch = $Resp[$i]
    if ($ch -eq '\') {
      $next = $Resp[$i + 1]
      if ($null -eq $next) { break }
      if     ($next -eq '"')  { $payload += '"' }
      elseif ($next -eq '\')  { $payload += '\' }
      elseif ($next -eq 'n')  { $payload += "`n" }
      elseif ($next -eq 'r')  { $payload += "`r" }
      elseif ($next -eq 't')  { $payload += "`t" }
      elseif ($next -eq 'u')  {
        if ($i + 5 -lt $Resp.Length) {
          $hex = $Resp.Substring($i + 2, 4)
          $code = [Convert]::ToInt32($hex, 16)
          $payload += [char]$code
          $i += 6; continue
        }
      }
      else { $payload += $next }
      $i += 2
    }
    elseif ($ch -eq '"') { break }
    else { $payload += $ch; $i++ }
  }
  return $payload
}

# Enable Page domain
[void](Invoke-Cdp -Method 'Page.enable')

# Navigate to page 1
Write-Output "=== Navigating to page 1 ==="
$navUrl = $BaseURL -replace 'start=\d+', 'start=0'
[void](Invoke-Cdp -Method 'Page.navigate' -Params @{ url = $navUrl })
Start-Sleep -Seconds 6

# Wait until cards rendered
$readyExpr = @'
(() => {
  const cards = document.querySelectorAll('div[data-job-id]');
  if (cards.length === 0) return 'NOT_READY';
  return JSON.stringify({count: cards.length, start: new URL(location.href).searchParams.get('start')});
})()
'@
for ($i = 0; $i -lt 15; $i++) {
  $r = Invoke-Cdp -Method 'Runtime.evaluate' -Params @{ expression = $readyExpr; returnByValue = $true }
  $v = Extract-Value -Resp $r
  if ($v -and $v -ne 'NOT_READY' -and $v.StartsWith('{')) {
    Write-Output "Page 1 ready: $v"
    break
  }
  Start-Sleep -Seconds 1
}

# JS extract
$jsExtract = @'
(() => {
  const cards = document.querySelectorAll('div[data-job-id]');
  const seen = new Set();
  const out = [];
  for (const c of cards) {
    const jobId = c.getAttribute('data-job-id');
    if (!jobId || seen.has(jobId)) continue;
    seen.add(jobId);
    const linkEl = c.querySelector('a.job-card-container__link, a[href*="/jobs/view/"]');
    const title = (linkEl?.getAttribute('aria-label') || linkEl?.innerText || '').trim().split('\n')[0];
    const subtitleEl = c.querySelector('.artdeco-entity-lockup__subtitle');
    const company = subtitleEl ? subtitleEl.innerText.trim().split('\n')[0] : null;
    const captionEl = c.querySelector('.artdeco-entity-lockup__caption, ul.job-card-container__metadata-wrapper');
    const location = captionEl ? captionEl.innerText.replace(/\n+/g, ', ').trim() : '';
    const link = linkEl ? linkEl.href : null;
    if (!title || !company) continue;
    const allText = c.innerText.replace(/\n+/g, ' | ').slice(0, 500);
    let posted = null;
    const agoMatch = allText.match(/(\d+\s+(?:minute|hour|day|week|month|year)s?\s+ago)/i);
    if (agoMatch) posted = agoMatch[1];
    else if (/Just now/i.test(allText)) posted = 'Just now';
    else if (/Today/i.test(allText)) posted = 'Today';
    else if (/Yesterday/i.test(allText)) posted = 'Yesterday';
    else if (/Reposted/i.test(allText)) posted = 'Reposted';
    else if (/Actively reviewing/i.test(allText)) posted = 'Actively reviewing';
    const cleanTitle = title.replace(/\s+with verification$/i, '').trim();
    out.push({ title: cleanTitle, company, location, link, jobId, posted, flags: allText });
  }
  return JSON.stringify({ count: out.length, jobs: out });
})()
'@

function Extract-Page {
  param([string]$PageLabel)
  for ($i = 0; $i -lt 6; $i++) {
    [void](Invoke-Cdp -Method 'Runtime.evaluate' -Params @{ expression = 'window.scrollTo(0, document.body.scrollHeight); 1'; returnByValue = $true })
    Start-Sleep -Milliseconds 1000
  }
  $r = Invoke-Cdp -Method 'Runtime.evaluate' -Params @{ expression = $jsExtract; returnByValue = $true }
  $payload = Extract-Value -Resp $r
  if ($null -eq $payload -or $payload.Length -lt 10) {
    Write-Host "[ERROR] $PageLabel extract fail"
    return $null
  }
  Write-Host "[$PageLabel] $($payload.Length) chars"
  return $payload
}

function Click-Page {
  param([int]$PageNum, [int]$ExpectedStart)
  $js = "(() => { const btns = document.querySelectorAll('button[aria-label]'); for (const b of btns) { if (b.getAttribute('aria-label') === 'Page $PageNum') { b.click(); return 'CLICKED'; } } return 'NOT_FOUND'; })()"
  $r = Invoke-Cdp -Method 'Runtime.evaluate' -Params @{ expression = $js; returnByValue = $true }
  $v = Extract-Value -Resp $r
  Write-Output "CLICK_PAGE_$PageNum = $v"
  $startExpr = "new URL(location.href).searchParams.get('start') || '0'"
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 1
    $r2 = Invoke-Cdp -Method 'Runtime.evaluate' -Params @{ expression = $startExpr; returnByValue = $true }
    $cur = Extract-Value -Resp $r2
    if ($cur -eq "$ExpectedStart") {
      Write-Output "  start=$cur (page $PageNum loaded)"
      return
    }
  }
  Write-Output "  WARNING: start did not reach $ExpectedStart after 20s (current: $cur)"
}

# ---- Page 1 ----
$page1 = Extract-Page -PageLabel 'PAGE1'
[System.IO.File]::WriteAllText("$OutDir\$PagePrefix`1.json", $page1, [System.Text.UTF8Encoding]::new($false))

# ---- Page 2 ----
Click-Page -PageNum 2 -ExpectedStart 25
$page2 = Extract-Page -PageLabel 'PAGE2'
[System.IO.File]::WriteAllText("$OutDir\$PagePrefix`2.json", $page2, [System.Text.UTF8Encoding]::new($false))

# ---- Page 3 ----
Click-Page -PageNum 3 -ExpectedStart 50
$page3 = Extract-Page -PageLabel 'PAGE3'
[System.IO.File]::WriteAllText("$OutDir\$PagePrefix`3.json", $page3, [System.Text.UTF8Encoding]::new($false))

# ---- Close ----
$ws.CloseAsync('NormalClosure', 'done', $ct).Wait()
$ws.Dispose()
Write-Output "DONE"
