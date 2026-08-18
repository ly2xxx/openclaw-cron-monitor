# Proper LinkedIn scan using [data-job-id] selectors
# Uses CDP Page.navigate (doesn't kill WS) and waits for start= parameter to change

$ErrorActionPreference = 'Stop'
# ---- Paths (override with env vars for portability) ----
$ChromeDebug = 'http://localhost:9222'
$OriginHeader = 'http://localhost:9222'
$OutDir = if ($env:AI_JOB_MONITOR_DIR) { $env:AI_JOB_MONITOR_DIR } else { Join-Path $PSScriptRoot '.' }
$BaseURL = 'https://www.linkedin.com/jobs/search/?currentJobId=4415524750&f_TPR=r2592000&keywords=AI%20Engineer&location=Greater%20Glasgow%20Area'

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
[void](Invoke-Cdp -Method 'Page.navigate' -Params @{ url = "$BaseURL&start=0" })
Start-Sleep -Seconds 6

# Wait until cards rendered (poll for data-job-id count > 0)
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
    // Extract "X minutes/hours/days/weeks/months ago" or "Reposted"
    let posted = null;
    const agoMatch = allText.match(/(\d+\s+(?:minute|hour|day|week|month|year)s?\s+ago)/i);
    if (agoMatch) posted = agoMatch[1];
    else if (/Just now/i.test(allText)) posted = 'Just now';
    else if (/Today/i.test(allText)) posted = 'Today';
    else if (/Yesterday/i.test(allText)) posted = 'Yesterday';
    else if (/Reposted/i.test(allText)) posted = 'Reposted';
    else if (/Actively reviewing/i.test(allText)) posted = 'Actively reviewing';
    // Promoted / with verification label often follows the title; strip it for cleanliness
    const cleanTitle = title.replace(/\s+with verification$/i, '').trim();
    out.push({ title: cleanTitle, company, location, link, jobId, posted, flags: allText });
  }
  return JSON.stringify({ count: out.length, jobs: out });
})()
'@

function Extract-Page {
  param([string]$PageLabel)
  # Scroll to trigger lazy loading
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
  # Clear the success stream so only the payload is captured by callers
  return $payload
}

function Click-Page {
  param([int]$PageNum, [int]$ExpectedStart)
  $js = "(() => { const btns = document.querySelectorAll('button[aria-label]'); for (const b of btns) { if (b.getAttribute('aria-label') === 'Page $PageNum') { b.click(); return 'CLICKED'; } } return 'NOT_FOUND'; })()"
  $r = Invoke-Cdp -Method 'Runtime.evaluate' -Params @{ expression = $js; returnByValue = $true }
  Write-Output "CLICK_PAGE_$PageNum RAW = $($r.Substring(0, [Math]::Min(300, $r.Length)))"
  $v = Extract-Value -Resp $r
  Write-Output "CLICK_PAGE_$PageNum = $v"
  # Wait until URL start= changes to expected value
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
[System.IO.File]::WriteAllText("$OutDir\linkedin-page1.json", $page1, [System.Text.UTF8Encoding]::new($false))

# ---- Page 2 ----
Click-Page -PageNum 2 -ExpectedStart 25
$page2 = Extract-Page -PageLabel 'PAGE2'
[System.IO.File]::WriteAllText("$OutDir\linkedin-page2.json", $page2, [System.Text.UTF8Encoding]::new($false))

# ---- Page 3 ----
Click-Page -PageNum 3 -ExpectedStart 50
$page3 = Extract-Page -PageLabel 'PAGE3'
[System.IO.File]::WriteAllText("$OutDir\linkedin-page3.json", $page3, [System.Text.UTF8Encoding]::new($false))

# ---- Close ----
$ws.CloseAsync('NormalClosure', 'done', $ct).Wait()
$ws.Dispose()
Write-Output "DONE"
