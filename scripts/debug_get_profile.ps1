# scripts/debug_get_profile.ps1
# Reproduce the 401 for users-manage?fn=get-profile
# Usage: .\scripts\debug_get_profile.ps1 -Token "eyJ..."
param(
  [string]$Token,
  [string]$BaseUrl = "https://lcelzrvpqwlbeccrwpkp.supabase.co/functions/v1",
  [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxjZWx6cnZwcXdsYmVjY3J3cGtwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQwMjgyMTAsImV4cCI6MjA5OTYwNDIxMH0.kSBD9jB8CFy1Oo5nTwtIslp-112dEP6bo1XszOuiPUU"
)

$headersAnon = @{
  "apikey" = $AnonKey
  "Authorization" = "Bearer $AnonKey"
  "Content-Type" = "application/json"
}
$headersUser = @{
  "apikey" = $AnonKey
  "Authorization" = "Bearer $Token"
  "Content-Type" = "application/json"
}

Write-Host "=== 1. ANON token (should 401 ANON_TOKEN) ===" -ForegroundColor Yellow
Invoke-RestMethod -Uri "$BaseUrl/users-manage?fn=get-profile" -Headers $headersAnon -Method Get -ErrorAction Continue | ConvertTo-Json -Depth 5

Write-Host "`n=== 2. USER token (should 200 or 401 with distinct code) ===" -ForegroundColor Yellow
if ($Token) {
  try {
    $res = Invoke-WebRequest -Uri "$BaseUrl/users-manage?fn=get-profile" -Headers $headersUser -Method Get -UseBasicParsing
    Write-Host "Status: $($res.StatusCode)"
    Write-Host $res.Content
  } catch {
    $resp = $_.Exception.Response
    if ($resp) {
      $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
      $body = $reader.ReadToEnd()
      Write-Host "Status: $($resp.StatusCode) $($resp.StatusDescription)"
      Write-Host "Body: $body"
      Write-Host "Headers: $($resp.Headers)"
    } else {
      Write-Host "Error: $_"
    }
  }
} else {
  Write-Host "Pass -Token to test user JWT"
}

Write-Host "`n=== 3. NO Authorization header (should 401 MISSING_HEADER) ===" -ForegroundColor Yellow
try {
  $res = Invoke-WebRequest -Uri "$BaseUrl/users-manage?fn=get-profile" -Headers @{"apikey"=$AnonKey} -Method Get -UseBasicParsing
} catch {
  $resp = $_.Exception.Response
  if ($resp) {
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $body = $reader.ReadToEnd()
    Write-Host "Status: $($resp.StatusCode)"
    Write-Host "Body: $body"
  }
}

Write-Host "`n=== 4. Decode JWT exp ===" -ForegroundColor Yellow
if ($Token) {
  $parts = $Token.Split('.')
  if ($parts.Length -ge 2) {
    $payload = $parts[1].PadRight($parts[1].Length + (4 - $parts[1].Length % 4) % 4, '=').Replace('-','+').Replace('_','/')
    $json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
    Write-Host $json
    $obj = $json | ConvertFrom-Json
    $exp = [DateTimeOffset]::FromUnixTimeSeconds($obj.exp).UtcDateTime
    Write-Host "exp: $exp UTC (now: $([DateTime]::UtcNow))"
    Write-Host "role: $($obj.role) sub: $($obj.sub)"
  }
}
