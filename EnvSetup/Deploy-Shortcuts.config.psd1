# Copy or edit this file next to Deploy-Shortcuts.ps1 (same folder).
# Values here apply only when the matching parameter was not passed on the command line.
# Environment variables override config when the parameter was not passed:
#   DEPLOY_SHORTCUTS_SOURCE_DIR, DEPLOY_SHORTCUTS_PREFIX,
#   DEPLOY_SHORTCUTS_START_NUM, DEPLOY_SHORTCUTS_END_NUM, DEPLOY_SHORTCUTS_SMB_USER
@{
    SourceDir = '\\LPW003ASI037\C$\Shortcuts'
    Prefix    = 'WLS111WCC'
    StartNum  = 1
    EndNum    = 164
    # SmbUser = 'user@domain.tld'
}
