[CmdletBinding()]
param([string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Check the implementation, timer hook, persistence, and both UI entries. A
# surviving comment or one setting name alone is not proof that AutoSkip works.
$checks = @{
    'src/mpc-hc/MainFrm.cpp' = @(
        'void\s+CMainFrame::AutoSkipChapterIfNeeded\s*\(\s*\)\s*\{',
        '(?s)case\s+TIMER_STREAMPOSPOLLER\s*:(?:(?!\bcase\b).)*?AutoSkipChapterIfNeeded\s*\(\s*\)\s*;'
    )
    'src/mpc-hc/MainFrm.h' = @('void\s+AutoSkipChapterIfNeeded\s*\(\s*\)\s*;', 'long\s+m_nLastAutoSkipChapter\s*=')
    'src/mpc-hc/AppSettings.h' = @('bool\s+bAutoSkipChapters\s*;', 'CString\s+sAutoSkipChapterPatterns\s*;')
    'src/mpc-hc/AppSettings.cpp' = @(
        'bAutoSkipChapters\s*=\s*!!pApp->GetProfileInt\(IDS_R_SETTINGS,\s*IDS_RS_AUTOSKIP_CHAPTERS',
        'sAutoSkipChapterPatterns\s*=\s*pApp->GetProfileString\(IDS_R_SETTINGS,\s*IDS_RS_AUTOSKIP_CHAPTER_PATTERNS',
        'pApp->WriteProfileInt\(IDS_R_SETTINGS,\s*IDS_RS_AUTOSKIP_CHAPTERS,\s*bAutoSkipChapters\)',
        'pApp->WriteProfileString\(IDS_R_SETTINGS,\s*IDS_RS_AUTOSKIP_CHAPTER_PATTERNS,\s*sAutoSkipChapterPatterns\)'
    )
    'src/mpc-hc/PPageAdvanced.cpp' = @('addBoolItem\s*\(\s*AUTOSKIP_CHAPTERS\s*,', 'addCStringItem\s*\(\s*AUTOSKIP_CHAPTER_PATTERNS\s*,')
    'src/mpc-hc/PPageAdvanced.h' = @('(?m)^\s*AUTOSKIP_CHAPTERS\s*,', '(?m)^\s*AUTOSKIP_CHAPTER_PATTERNS\s*,')
    'src/mpc-hc/SettingsDefines.h' = @('#define\s+IDS_RS_AUTOSKIP_CHAPTERS\s+_T\("AutoSkipChapters"\)', '#define\s+IDS_RS_AUTOSKIP_CHAPTER_PATTERNS\s+_T\("AutoSkipChapterPatterns"\)')
}

foreach ($item in $checks.GetEnumerator()) {
    $path = Join-Path $RepoRoot $item.Key
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing file: $($item.Key)"
    }
    $text = [IO.File]::ReadAllText($path)
    if ($text -match '(?m)^(?:<{7}|={7}|>{7})(?: .*)?\r?$') { throw "Unresolved conflict markers in $($item.Key)" }
    foreach ($pattern in $item.Value) {
        $count = [regex]::Matches($text, $pattern).Count
        if ($count -ne 1) { throw "AutoSkip verification failed in $($item.Key): expected exactly one '$pattern', found $count." }
    }
}

Write-Host 'AutoSkip implementation, timer hook, settings persistence, and UI verified.' -ForegroundColor Green
