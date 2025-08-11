# SysAdminSuite Simple Release Script
# This script creates a new release for SysAdminSuite

param(
    [ValidateSet('patch','minor','major')]
    [string]$Bump = 'patch'
)

# Set working directory
Set-Location 'C:\Users\Cheex\Desktop\dev\config\github\SysAdminSuite'

# Read current version from version_manager.py
$versionContent = Get-Content .\version_manager.py -Raw
$versionMatch = [regex]::Match($versionContent, 'VERSION\s*=\s*["''](\d+\.\d+\.\d+)["'']')
if (-not $versionMatch.Success) {
    Write-Host "Could not find VERSION in version_manager.py" -ForegroundColor Red
    exit 1
}

$currentVersion = $versionMatch.Groups[1].Value
Write-Host "Current version: $currentVersion" -ForegroundColor Green

# Bump version
$versionParts = $currentVersion -split '\.'
$major = [int]$versionParts[0]
$minor = [int]$versionParts[1]
$patch = [int]$versionParts[2]

switch ($Bump) {
    'major' { 
        $major++
        $minor = 0
        $patch = 0
    }
    'minor' { 
        $minor++
        $patch = 0
    }
    'patch' { 
        $patch++
    }
}

$newVersion = "$major.$minor.$patch"
$tagVersion = "v$newVersion"

Write-Host "New version: $newVersion" -ForegroundColor Green

# Update version in version_manager.py
$newContent = $versionContent -replace 'VERSION\s*=\s*["'']\d+\.\d+\.\d+["'']', "VERSION = `"$newVersion`""
Set-Content -Path .\version_manager.py -Value $newContent -Encoding UTF8

# Git operations
git add version_manager.py
git commit -m "chore(version): bump to $tagVersion"
git tag -a $tagVersion -m "Release $tagVersion: SysAdminSuite IT tools collection"
git push origin main
git push origin $tagVersion

Write-Host "Release $tagVersion created successfully!" -ForegroundColor Green
