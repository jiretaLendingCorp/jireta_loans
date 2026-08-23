# scripts/debug_notifications.ps1 – mirror of debug_get_profile but for notifications-view
param(
  [string]$Token,
  [string]$BaseUrl = "https://lcelzrvpqwlbeccrwpkp.supabase.co/functions/v1",
  [string]$AnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxjZWx6cnZwcXdsYmVjY3J3cGtwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQwMjgyMTAsImV4cCI6MjA5OTYwNDIxMH0.kSBD9jB8CFy1Oo5nTwtIslp-112dEP6bo1XszOuiPUU"
)
$hAnon = @{ "apikey"=$AnonKey; "Authorization"="Bearer $AnonKey" }
$hUser = @{ "apikey"=$AnonKey; "Authorization"="Bearer $Token" }
Write-Host "=== notifications-view ANON (expect 401 ANON_TOKEN) ===" -ForegroundColor Yellow
try { Invoke-WebRequest -Uri "$BaseUrl/notifications-view?fn=get-list&page=1&limit=20" -Headers $hAnon -Method Get -UseBasicParsing | Out-Null } catch {
  $r=$_.Exception.Response; $reader=New-Object System.IO.StreamReader($r.GetResponseStream()); Write-Host "Status $($r.StatusCode) Body: $($reader.ReadToEnd())"
}
if ($Token) {
  Write-Host "`n=== notifications-view USER (expect 200 or distinct 401) ===" -ForegroundColor Yellow
  try {
    $res=Invoke-WebRequest -Uri "$BaseUrl/notifications-view?fn=get-list&page=1&limit=20" -Headers $hUser -Method Get -UseBasicParsing
    Write-Host "Status $($res.StatusCode)`n$($res.Content.Substring(0,500))"
  } catch {
    $r=$_.Exception.Response; $reader=New-Object System.IO.StreamReader($r.GetResponseStream()); Write-Host "Status $($r.StatusCode) Body: $($reader.ReadToEnd())"
  }
}
