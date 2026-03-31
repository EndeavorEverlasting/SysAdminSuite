#Requires -Modules Pester
<#
.SYNOPSIS
    Offline tests for OCR fixtures in the OCR folder.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:fixturePath = Join-Path $script:repoRoot "OCR\Jude's 2026 Buildout Project.pdf"
    $script:ocrScriptPath = Join-Path $script:repoRoot 'OCR\locus_mapping_ocr.py'
    $script:corePath = Join-Path $script:repoRoot 'OCR\map_parse_core.py'
    $script:wsParserPath = Join-Path $script:repoRoot 'OCR\parse_workstation_map.py'
    $script:prParserPath = Join-Path $script:repoRoot 'OCR\parse_printer_map.py'
}

Describe 'OCR known-bad fixture contracts' {
    It 'Known-bad fixture exists and is a PDF sample' {
        $script:fixturePath | Should -Exist
        [System.IO.Path]::GetExtension($script:fixturePath).ToLowerInvariant() | Should -Be '.pdf'
    }

    It 'Fixture fails practical OCR pipeline execution when dependencies are available' {
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if (-not $pythonCmd) {
            Set-ItResult -Skipped -Because 'python was not found on PATH'
            return
        }

        $tmpPrefix = Join-Path ([System.IO.Path]::GetTempPath()) ("sas-ocr-knownbad-" + [guid]::NewGuid().ToString('N'))
        $stdoutPath = "$tmpPrefix.stdout.txt"
        $stderrPath = "$tmpPrefix.stderr.txt"
        $scriptArgs = @(
            $script:ocrScriptPath
            '--workstations', $script:fixturePath
            '--printers', $script:fixturePath
            '--out-prefix', $tmpPrefix
        )

        try {
            $proc = Start-Process -FilePath $pythonCmd.Source -ArgumentList $scriptArgs -NoNewWindow -PassThru -Wait -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
            $output = ''
            if (Test-Path -LiteralPath $stdoutPath) { $output += (Get-Content -Path $stdoutPath -Raw -ErrorAction SilentlyContinue) }
            if (Test-Path -LiteralPath $stderrPath) { $output += "`n" + (Get-Content -Path $stderrPath -Raw -ErrorAction SilentlyContinue) }

            if ($output -match 'ModuleNotFoundError|No module named|ImportError') {
                Set-ItResult -Skipped -Because 'python OCR dependencies are not installed in this environment'
                return
            }

            # Known-bad fixture: either OpenCV rejects the PDF input, or output is too weak to produce mapping CSVs.
            $wsCsv = "$tmpPrefix-workstations.csv"
            $prCsv = "$tmpPrefix-printers.csv"
            $nearestCsv = "$tmpPrefix-nearest.csv"

            $cannotRead = $output -match 'Cannot read workstation image|Cannot read printer image'
            $missingUsefulOutputs = -not ((Test-Path -LiteralPath $wsCsv) -and (Test-Path -LiteralPath $prCsv) -and (Test-Path -LiteralPath $nearestCsv))

            (($proc.ExitCode -ne 0) -or $cannotRead -or $missingUsefulOutputs) | Should -BeTrue -Because 'this low-resolution PDF fixture is intentionally unsuitable as a practical OCR source map'
        }
        finally {
            @("$tmpPrefix.stdout.txt", "$tmpPrefix.stderr.txt", "$tmpPrefix-overlay-ws.png", "$tmpPrefix-overlay-pr.png", "$tmpPrefix-workstations.csv", "$tmpPrefix-printers.csv", "$tmpPrefix-nearest.csv") |
                ForEach-Object {
                    if (Test-Path -LiteralPath $_) {
                        Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue
                    }
                }
        }
    }
}

Describe 'OCR parser engine contracts' {
    It 'Core module and parser entrypoints exist' {
        $script:corePath | Should -Exist
        $script:wsParserPath | Should -Exist
        $script:prParserPath | Should -Exist
    }

    It 'Workstation parser imports shared core and writes WorkstationID output' {
        $content = Get-Content -Path $script:wsParserPath -Raw
        $content | Should -Match 'from map_parse_core import'
        $content | Should -Match 'WorkstationID'
        $content | Should -Match 'parse_args_common'
    }

    It 'Printer parser imports shared core and writes PrinterID output' {
        $content = Get-Content -Path $script:prParserPath -Raw
        $content | Should -Match 'from map_parse_core import'
        $content | Should -Match 'PrinterID'
        $content | Should -Match 'parse_args_common'
    }

    It 'Shared core supports PDF loading and quality summary helpers' {
        $content = Get-Content -Path $script:corePath -Raw
        $content | Should -Match 'def load_map_bgr'
        $content | Should -Match 'pypdfium2'
        $content | Should -Match 'def summarize_quality'
        $content | Should -Match 'if mask is None'
        $content | Should -Match 'np\.zeros\(hsv\.shape\[:2\], dtype=np\.uint8\)'
        $content | Should -Match 'cv2\.morphologyEx'
        $content | Should -Match 'def compare_detected_to_legend'
        $content | Should -Match 'def ocr_digits_with_confidence'
    }

    It 'Parsers expose confidence and legend comparison arguments' {
        $wsContent = Get-Content -Path $script:wsParserPath -Raw
        $prContent = Get-Content -Path $script:prParserPath -Raw
        $coreContent = Get-Content -Path $script:corePath -Raw

        $coreContent | Should -Match '--out-html'
        $wsContent | Should -Match '--confidence-threshold'
        $wsContent | Should -Match '--legend-right-ratio'
        $wsContent | Should -Match '--legend-keyword'
        $wsContent | Should -Match '--out-summary-json'
        $wsContent | Should -Match 'write_universal_html_report'

        $coreContent | Should -Match '--out-html'
        $prContent | Should -Match '--confidence-threshold'
        $prContent | Should -Match '--legend-right-ratio'
        $prContent | Should -Match '--legend-keyword'
        $prContent | Should -Match '--out-summary-json'
        $prContent | Should -Match 'write_universal_html_report'
    }
}
