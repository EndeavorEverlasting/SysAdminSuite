# SysAdminSuite Version Management Guide

This guide explains how to use the version management system in SysAdminSuite, which is designed to make development and releases a breeze.

## Overview

The version management system provides:
- **Centralized version tracking** across all tools
- **Automated version bumping** with semantic versioning
- **Git integration** for automatic tagging and releases
- **Consistent documentation** updates

## Key Files

### Core Version Files
- `version_manager.py` - **Single source of truth** for version information
- `release_manager.py` - Python-based release automation tool
- `CHANGELOG.md` - Detailed change history
- `VERSION_TEMPLATE.md` - Template for version documentation

### Git Tools
- `git/Cut-Release.ps1` - PowerShell release script (advanced)
- `git/Cut-Release-Simple.ps1` - Simplified PowerShell release script
- `git/Upload to GitHub.ps1` - GitHub upload automation

## Quick Start

### 1. Check Current Version
```bash
# Using Python
python version_manager.py

# Using batch file (Windows)
check_version.bat
```

### 2. Create a New Release
```bash
# Patch release (bug fixes)
python release_manager.py patch

# Minor release (new features)
python release_manager.py minor

# Major release (breaking changes)
python release_manager.py major
```

### 3. Create Release Without Pushing
```bash
python release_manager.py patch --no-push
```

## Version Numbering

SysAdminSuite follows [Semantic Versioning](https://semver.org/):

- **MAJOR** (X.0.0): Breaking changes, major new features, new tool additions
- **MINOR** (X.Y.0): New features, enhancements, backward-compatible changes
- **PATCH** (X.Y.Z): Bug fixes, security patches, minor improvements

### Examples
- `1.0.0` → `1.0.1` (patch: bug fix)
- `1.0.1` → `1.1.0` (minor: new feature)
- `1.1.0` → `2.0.0` (major: breaking change)

## Workflow Examples

### Adding a New Tool
1. Create your tool in the appropriate category
2. Test thoroughly
3. Update version if needed:
   ```bash
   python release_manager.py minor
   ```
4. Update `CHANGELOG.md` with new features
5. Push changes

### Bug Fix Release
1. Fix the bug
2. Test the fix
3. Create patch release:
   ```bash
   python release_manager.py patch
   ```
4. Update `CHANGELOG.md` with fix details

### Major Feature Release
1. Implement major features
2. Test extensively
3. Create major release:
   ```bash
   python release_manager.py major
   ```
4. Update documentation
5. Update `CHANGELOG.md` with breaking changes

## Advanced Usage

### PowerShell Scripts
For advanced users, PowerShell scripts provide additional features:

```powershell
# Create release with pull request
.\git\Cut-Release.ps1 -Bump patch -OpenPR

# Create release without updating version file
.\git\Cut-Release.ps1 -Bump patch -NoWriteMain

# Create development release
.\git\Cut-Release.ps1 -Prefix dev -Bump minor
```

### Manual Version Updates
If you need to manually update the version:

1. Edit `version_manager.py`:
   ```python
   VERSION = "1.2.3"  # Change this line
   ```

2. Update `CHANGELOG.md` with new version entry

3. Update `README.md` version badge

4. Commit and tag:
   ```bash
   git add .
   git commit -m "chore(version): bump to v1.2.3"
   git tag -a v1.2.3 -m "Release v1.2.3"
   git push origin main
   git push origin v1.2.3
   ```

## Best Practices

### 1. Always Use the Release Manager
Instead of manually editing version numbers, use:
```bash
python release_manager.py [patch|minor|major]
```

### 2. Update Changelog
Always document changes in `CHANGELOG.md`:
```markdown
## [v1.2.3] - 2024-01-15

### Added
- New printer mapping tool
- Enhanced configuration validation

### Fixed
- Resolved Windows registry path issue
```

### 3. Test Before Release
- Test all tools in the collection
- Verify version numbers are consistent
- Check documentation is up to date

### 4. Use Descriptive Commit Messages
```bash
git commit -m "feat(printer): add network printer mapping tool"
git commit -m "fix(config): resolve Windows registry path issue"
git commit -m "docs(readme): update installation instructions"
```

## Troubleshooting

### Version Not Found Error
If you get "Could not find VERSION in version_manager.py":
1. Check that `version_manager.py` exists
2. Verify the VERSION line format: `VERSION = "1.2.3"`
3. Ensure no extra spaces or characters

### Git Push Errors
If git push fails:
1. Check your git credentials are configured
2. Verify you have push access to the repository
3. Ensure the remote is correctly set up

### PowerShell Script Issues
If PowerShell scripts fail:
1. Check PowerShell execution policy: `Get-ExecutionPolicy`
2. Run as administrator if needed
3. Use the Python release manager as an alternative

## Integration with CI/CD

The version management system can be integrated with CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Create Release
  run: |
    python release_manager.py patch
    git push origin main
    git push origin $(python -c "import version_manager; print('v' + version_manager.VERSION)")
```

## Migration from Other Systems

If migrating from another versioning system:

1. Set the current version in `version_manager.py`
2. Create initial tag: `git tag -a v1.0.0 -m "Initial release"`
3. Push tag: `git push origin v1.0.0`
4. Start using the release manager for future releases

## Support

For issues with version management:
1. Check this guide
2. Review the `CHANGELOG.md` for examples
3. Check the `VERSION_TEMPLATE.md` for templates
4. Create an issue on GitHub

## Future Enhancements

Planned improvements to the version management system:
- [ ] Web-based version dashboard
- [ ] Automated dependency updates
- [ ] Integration with package managers
- [ ] Advanced release notes generation
- [ ] Multi-repository version synchronization
