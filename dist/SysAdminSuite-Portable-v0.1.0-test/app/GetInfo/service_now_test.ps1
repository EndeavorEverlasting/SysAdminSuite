# ===== Test ServiceNow API Connection =====
$User = "rperez26"
$Pass = "NVV$t@nd@rdP@$$"

$pair = "$($User):$($Pass)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{ Authorization = "Basic $encodedCreds" }

$baseUrl = "https://northwell.service-now.com/api/now/table/cmdb_ci_computer"
$hostname = "WLS111WCC001"
$uri = "$baseUrl?sysparm_query=name=$hostname&sysparm_limit=1"

try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    if ($response.result) {
        Write-Host "✅ API access works!"
        $response.result | Format-List name, asset_tag, serial_number, model_id
    } else {
        Write-Host "⚠️ No result returned. API access may be limited."
    }
}
catch {
    Write-Host "❌ API test failed. Error was:" $_.Exception.Message
}
