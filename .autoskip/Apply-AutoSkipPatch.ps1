[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    $enc = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

$script:PendingFiles = @{}

function Replace-Once {
    param(
        [Parameter(Mandatory)] [string]$RelativePath,
        [Parameter(Mandatory)] [string]$Needle,
        [Parameter(Mandatory)] [string]$Replacement
    )

    $path = Join-Path $RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Patch target missing: $RelativePath"
    }

    if ($script:PendingFiles.ContainsKey($RelativePath)) {
        $text = $script:PendingFiles[$RelativePath]
    } else {
        $text = [System.IO.File]::ReadAllText($path)
    }

    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $needleNative = $Needle -replace "`r?`n", $newline
    $replacementNative = $Replacement -replace "`r?`n", $newline
    $idx = $text.IndexOf($needleNative, [System.StringComparison]::Ordinal)
    if ($idx -lt 0) {
        throw "Patch anchor not found in $RelativePath. Upstream likely changed; no source files have been written."
    }

    $script:PendingFiles[$RelativePath] = $text.Substring(0, $idx) + $replacementNative + $text.Substring($idx + $needleNative.Length)
    Write-Host "Prepared patch for $RelativePath" -ForegroundColor DarkGreen
}

$mainFrmCpp = Join-Path $RepoRoot 'src/mpc-hc/MainFrm.cpp'
if (-not (Test-Path -LiteralPath $mainFrmCpp)) {
    throw "This does not look like an MPC-HC source tree: $RepoRoot"
}

if ([System.IO.File]::ReadAllText($mainFrmCpp).Contains('MPC-HC AutoSkip: chapter matcher')) {
    Write-Host 'AutoSkip patch is already present; nothing to do.' -ForegroundColor Yellow
    exit 0
}

# 1) Persistent setting names.
Replace-Once 'src/mpc-hc/SettingsDefines.h' @'
#define IDS_RS_LOOP_FOLDER_NEXT_FILE        _T("LoopFolderOnPlayNextFile")
'@ @'
#define IDS_RS_LOOP_FOLDER_NEXT_FILE        _T("LoopFolderOnPlayNextFile")
#define IDS_RS_AUTOSKIP_CHAPTERS            _T("AutoSkipChapters")
#define IDS_RS_AUTOSKIP_CHAPTER_PATTERNS    _T("AutoSkipChapterPatterns")
'@

# 2) CAppSettings fields.
Replace-Once 'src/mpc-hc/AppSettings.h' @'
    bool            bAllowInaccurateFastseek;
    bool            bLoopFolderOnPlayNextFile;
    bool            bNextFileInFolderSortByDate;
'@ @'
    bool            bAllowInaccurateFastseek;
    bool            bLoopFolderOnPlayNextFile;
    bool            bAutoSkipChapters;
    CString         sAutoSkipChapterPatterns;
    bool            bNextFileInFolderSortByDate;
'@

# 3) Defaults are supplied by the normal settings load calls below.

# 4) Load settings.
Replace-Once 'src/mpc-hc/AppSettings.cpp' @'
    bAllowInaccurateFastseek = !!pApp->GetProfileInt(IDS_R_SETTINGS, IDS_RS_ALLOW_INACCURATE_FASTSEEK, FALSE);
    bLoopFolderOnPlayNextFile = !!pApp->GetProfileInt(IDS_R_SETTINGS, IDS_RS_LOOP_FOLDER_NEXT_FILE, FALSE);
    bNextFileInFolderSortByDate = !!pApp->GetProfileInt(IDS_R_SETTINGS, IDS_RS_NEXT_FILE_SORT_BY_DATE, FALSE);
'@ @'
    bAllowInaccurateFastseek = !!pApp->GetProfileInt(IDS_R_SETTINGS, IDS_RS_ALLOW_INACCURATE_FASTSEEK, FALSE);
    bLoopFolderOnPlayNextFile = !!pApp->GetProfileInt(IDS_R_SETTINGS, IDS_RS_LOOP_FOLDER_NEXT_FILE, FALSE);
    bAutoSkipChapters = !!pApp->GetProfileInt(IDS_R_SETTINGS, IDS_RS_AUTOSKIP_CHAPTERS, TRUE);
    sAutoSkipChapterPatterns = pApp->GetProfileString(IDS_R_SETTINGS, IDS_RS_AUTOSKIP_CHAPTER_PATTERNS, _T("opening;ending;yokoku;preview"));
    bNextFileInFolderSortByDate = !!pApp->GetProfileInt(IDS_R_SETTINGS, IDS_RS_NEXT_FILE_SORT_BY_DATE, FALSE);
'@

# 5) Save settings.
Replace-Once 'src/mpc-hc/AppSettings.cpp' @'
    pApp->WriteProfileInt(IDS_R_SETTINGS, IDS_RS_ALLOW_INACCURATE_FASTSEEK, bAllowInaccurateFastseek);
    pApp->WriteProfileInt(IDS_R_SETTINGS, IDS_RS_LOOP_FOLDER_NEXT_FILE, bLoopFolderOnPlayNextFile);
    pApp->WriteProfileInt(IDS_R_SETTINGS, IDS_RS_NEXT_FILE_SORT_BY_DATE, bNextFileInFolderSortByDate);
'@ @'
    pApp->WriteProfileInt(IDS_R_SETTINGS, IDS_RS_ALLOW_INACCURATE_FASTSEEK, bAllowInaccurateFastseek);
    pApp->WriteProfileInt(IDS_R_SETTINGS, IDS_RS_LOOP_FOLDER_NEXT_FILE, bLoopFolderOnPlayNextFile);
    pApp->WriteProfileInt(IDS_R_SETTINGS, IDS_RS_AUTOSKIP_CHAPTERS, bAutoSkipChapters);
    pApp->WriteProfileString(IDS_R_SETTINGS, IDS_RS_AUTOSKIP_CHAPTER_PATTERNS, sAutoSkipChapterPatterns);
    pApp->WriteProfileInt(IDS_R_SETTINGS, IDS_RS_NEXT_FILE_SORT_BY_DATE, bNextFileInFolderSortByDate);
'@

# 6) Add the settings to Options > Advanced > Playback.
Replace-Once 'src/mpc-hc/PPageAdvanced.h' @'
        LOOP_FOLDER_NEXT_FILE,
        NEXT_FILE_SORT_BY_DATE,
'@ @'
        LOOP_FOLDER_NEXT_FILE,
        AUTOSKIP_CHAPTERS,
        AUTOSKIP_CHAPTER_PATTERNS,
        NEXT_FILE_SORT_BY_DATE,
'@

Replace-Once 'src/mpc-hc/PPageAdvanced.cpp' @'
    addBoolItem(LOOP_FOLDER_NEXT_FILE, IDS_RS_LOOP_FOLDER_NEXT_FILE, false, s.bLoopFolderOnPlayNextFile, StrRes(IDS_PPAGEADVANCED_LOOP_FOLDER_NEXT_FILE));
    addBoolItem(NEXT_FILE_SORT_BY_DATE, IDS_RS_NEXT_FILE_SORT_BY_DATE, false, s.bNextFileInFolderSortByDate, L"Sort files by creation time instead of file name when skipping to the next/previous file in a folder.");
'@ @'
    addBoolItem(LOOP_FOLDER_NEXT_FILE, IDS_RS_LOOP_FOLDER_NEXT_FILE, false, s.bLoopFolderOnPlayNextFile, StrRes(IDS_PPAGEADVANCED_LOOP_FOLDER_NEXT_FILE));
    addBoolItem(AUTOSKIP_CHAPTERS, L"AutoSkipChapters", true, s.bAutoSkipChapters, L"Automatically skip file chapters whose title matches AutoSkipChapterPatterns.");
    addCStringItem(AUTOSKIP_CHAPTER_PATTERNS, L"AutoSkipChapterPatterns", L"opening;ending;yokoku;preview", s.sAutoSkipChapterPatterns, L"Semicolon-separated, case-insensitive substrings. Example: opening;ending;yokoku;preview");
    addBoolItem(NEXT_FILE_SORT_BY_DATE, IDS_RS_NEXT_FILE_SORT_BY_DATE, false, s.bNextFileInFolderSortByDate, L"Sort files by creation time instead of file name when skipping to the next/previous file in a folder.");
'@

# 7) CMainFrame declaration/state.
Replace-Once 'src/mpc-hc/MainFrm.h' @'
    EventClient m_eventc;
    void EventCallback(MpcEvent ev);
'@ @'
    EventClient m_eventc;
    void EventCallback(MpcEvent ev);
    void AutoSkipChapterIfNeeded();
'@

Replace-Once 'src/mpc-hc/MainFrm.h' @'
    UINT m_nLastSkipDirection;

    int m_iStreamPosPollerInterval;
'@ @'
    UINT m_nLastSkipDirection;
    long m_nLastAutoSkipChapter = -1;

    int m_iStreamPosPollerInterval;
'@

# 8) Native implementation. It uses MPC-HC's own chapter bag and posts the existing
#    Next Chapter command, so the normal last-chapter -> next-file behavior remains intact.
Replace-Once 'src/mpc-hc/MainFrm.cpp' @'
void CMainFrame::OnTimer(UINT_PTR nIDEvent)
'@ @'
// MPC-HC AutoSkip: chapter matcher
void CMainFrame::AutoSkipChapterIfNeeded()
{
    const CAppSettings& s = AfxGetAppSettings();

    if (!s.bAutoSkipChapters
            || s.sAutoSkipChapterPatterns.IsEmpty()
            || GetPlaybackMode() != PM_FILE
            || GetMediaState() != State_Running
            || !m_pMS
            || !m_pCB) {
        m_nLastAutoSkipChapter = -1;
        return;
    }

    REFERENCE_TIME rtNow = 0;
    if (FAILED(m_pMS->GetCurrentPosition(&rtNow))) {
        return;
    }

    CComBSTR bstr;
    const long currentChap = m_pCB->ChapLookup(&rtNow, &bstr);
    if (currentChap < 0 || !bstr.Length()) {
        m_nLastAutoSkipChapter = -1;
        return;
    }

    CString title(bstr.m_str);
    CString titleLower(title);
    titleLower.MakeLower();

    bool match = false;
    int pos = 0;
    do {
        CString token = s.sAutoSkipChapterPatterns.Tokenize(_T(";"), pos);
        token.Trim();
        token.MakeLower();
        if (!token.IsEmpty() && titleLower.Find(token) >= 0) {
            match = true;
            break;
        }
    } while (pos != -1);

    if (!match) {
        m_nLastAutoSkipChapter = -1;
        return;
    }

    // Debounce the stream-position timer. A subsequent matching chapter has a
    // different index and can therefore be skipped immediately as well.
    if (m_nLastAutoSkipChapter == currentChap) {
        return;
    }

    m_nLastAutoSkipChapter = currentChap;
    PostMessage(WM_COMMAND, ID_NAVIGATE_SKIPFORWARD);
}

void CMainFrame::OnTimer(UINT_PTR nIDEvent)
'@

# 9) Run AutoSkip from MPC-HC's existing stream-position poller.
Replace-Once 'src/mpc-hc/MainFrm.cpp' @'
        case TIMER_STREAMPOSPOLLER:
            if (GetLoadState() == MLS::LOADED) {
'@ @'
        case TIMER_STREAMPOSPOLLER:
            if (GetLoadState() == MLS::LOADED) {
                AutoSkipChapterIfNeeded();
'@

# Commit all prepared source edits only after every anchor has been validated.
foreach ($entry in $script:PendingFiles.GetEnumerator()) {
    $path = Join-Path $RepoRoot $entry.Key
    Write-Utf8NoBom -Path $path -Text $entry.Value
    Write-Host "Patched $($entry.Key)" -ForegroundColor Green
}

Write-Host ''
Write-Host 'MPC-HC AutoSkip patch applied successfully.' -ForegroundColor Cyan
Write-Host 'UI: Options > Advanced > Playback > AutoSkipChapters / AutoSkipChapterPatterns'
