# Define the repository name and description
$repoName = "SysAdminSuite"
$repoDescription = "A collection of IT tools for configs, installs, printer mapping, remote solutions, and tests."

# Create a new directory for the repository
$repoPath = "C:\path\to\your\repositories\$repoName"
New-Item -ItemType Directory -Path $repoPath

# Initialize a new Git repository
Set-Location -Path $repoPath
git init

# Create a README file
$readmeContent = @"
# $repoName

$repoDescription

## Table of Contents

- [Configs](#configs)
- [Installs](#installs)
- [Printer Mapping](#printer-mapping)
- [Remote Solutions](#remote-solutions)
- [Tests](#tests)

## Configs

## Installs

## Printer Mapping

## Remote Solutions

## Tests
"@
$readmeContent | Out-File -FilePath "README.md" -Encoding utf8

# Add the README file to the repository
git add README.md

# Commit the initial files
git commit -m "Initial commit"

# Create a new private repository on GitHub
gh repo create $repoName --private --description "$repoDescription"

# Add the GitHub repository as a remote
$githubUrl = "https://github.com/your-username/$repoName.git"
git remote add origin $githubUrl

# Push the initial commit to the GitHub repository
git push -u origin master

Write-Host "Repository $repoName has been created and initialized on GitHub."
