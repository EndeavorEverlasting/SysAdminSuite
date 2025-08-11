# Version Template for SysAdminSuite

This template should be used for each new version release to maintain consistency in documentation and versioning for the SysAdminSuite collection.

## Version Information
- **Version**: `vX.Y.Z` (e.g., v1.1.0, v1.2.3, v2.0.0)
- **Release Date**: YYYY-MM-DD
- **Release Type**: `Major` | `Minor` | `Patch`
- **Git Tag**: `vX.Y.Z`

## Version Numbering Convention
- **Major (X)**: Breaking changes, major new features, complete rewrites, new tool additions
- **Minor (Y)**: New features, enhancements, backward-compatible changes, new configurations
- **Patch (Z)**: Bug fixes, security patches, minor improvements, configuration updates

## Files to Update for Each Release

### 1. README.md
- Update version badge: `![Version](https://img.shields.io/badge/Version-X.Y.Z-orange.svg)`
- Update version link: `https://github.com/your-username/SysAdminSuite/releases/tag/vX.Y.Z`
- Update main title: `# SysAdminSuite vX.Y.Z`
- Add new version to changelog section

### 2. git/Upload to GitHub.ps1
- Update `$VERSION = 'vX.Y.Z'`
- Update commit message if needed
- Update branch name if following new naming convention

### 3. version_manager.py
- Update version in title: `VERSION = "X.Y.Z"`
- Update any version constants in the code

### 4. requirements.txt (if exists)
- Update dependency versions if changed
- Add new dependencies if added

### 5. CHANGELOG.md
- Add new version entry with detailed changes
- Follow [Keep a Changelog](https://keepachangelog.com/) format

## Release Checklist

### Pre-Release
- [ ] All tests passing
- [ ] Documentation updated
- [ ] Version numbers updated in all files
- [ ] Dependencies reviewed and updated
- [ ] Security audit completed
- [ ] Performance testing completed
- [ ] All tools in collection tested

### Release
- [ ] Create git tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
- [ ] Push tag: `git push origin vX.Y.Z`
- [ ] Create GitHub release with release notes
- [ ] Update any deployment scripts
- [ ] Notify stakeholders

### Post-Release
- [ ] Monitor for any issues
- [ ] Update development branch for next version
- [ ] Archive old version documentation if needed
- [ ] Update any external references

## Example Version Entry for Changelog

```markdown
## [vX.Y.Z] - YYYY-MM-DD

### Added
- New tool: [Tool Name] for [purpose]
- New configuration template for [system]
- New installation script for [software]

### Changed
- Updated [existing tool] with [improvement]
- Modified [configuration] behavior
- Enhanced [feature] performance

### Deprecated
- [Tool/feature] that will be removed in future version

### Removed
- Removed [tool/feature] description

### Fixed
- Bug fix in [tool/configuration]
- Security fix in [component]
- Configuration issue in [system]

### Security
- Security improvement in [component]
- Vulnerability fix in [tool]
```

## Branch Naming Convention

### Release Branches
- Format: `release/vX.Y.Z`
- Example: `release/v1.2.0`

### Feature Branches
- Format: `feature/description`
- Example: `feature/new-printer-mapping-tool`

### Hotfix Branches
- Format: `hotfix/description`
- Example: `hotfix/security-patch`

## Commit Message Convention

### Format
```
type(scope): description

[optional body]

[optional footer]
```

### Types
- `feat`: New feature or tool
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks
- `config`: Configuration changes
- `tool`: Tool-specific changes

### Examples
```
feat(printer): add network printer mapping tool
fix(config): resolve Windows registry path issue
docs(readme): update installation instructions
refactor(install): improve software installation process
config(windows): update Windows 11 compatibility
tool(remote): enhance remote desktop connection
```

## Version History Template

```markdown
## Version History

### [v1.0.0] - 2024-01-15
- **Initial Release**
- Core IT tools collection
- Configuration management utilities
- Installation automation scripts
- Printer mapping tools
- Remote access solutions
- Testing and validation tools
- Cross-platform support (Windows, macOS, Linux)

### [vX.Y.Z] - YYYY-MM-DD
- **Next Release**
- [Add features/changes here]
```

## Tool Categories

### Configs
- System configuration templates
- Registry modifications
- Environment setup scripts

### Installs
- Software installation automation
- Package management scripts
- Dependency installation tools

### Printer Mapping
- Network printer configuration
- Driver installation scripts
- Print server management

### Remote Solutions
- Remote desktop tools
- SSH configuration
- VPN setup scripts

### Tests
- System validation tools
- Performance testing scripts
- Security assessment utilities

## Notes
- Always test version updates thoroughly across all tools
- Keep version numbers consistent across all files
- Update this template if new requirements are discovered
- Consider using semantic versioning tools for automation
- Document any breaking changes clearly
- Test all tools in the collection before release
