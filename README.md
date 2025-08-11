# SysAdminSuite v1.0.0

A comprehensive collection of IT tools for system administration, configuration management, and automation.

![Version](https://img.shields.io/badge/Version-1.0.0-orange.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

## Overview

SysAdminSuite is a curated collection of IT tools designed to streamline system administration tasks, automate configurations, and provide reliable solutions for common IT challenges.

## Features

- **Version Management**: Centralized version tracking across all tools
- **Configuration Management**: Automated system configuration tools
- **Installation Automation**: Streamlined software installation scripts
- **Printer Management**: Network printer mapping and configuration
- **Remote Solutions**: Remote access and management tools
- **Testing & Validation**: Comprehensive testing and validation utilities
- **Cross-Platform Support**: Windows, macOS, and Linux compatibility

## Quick Start

### Prerequisites

- Python 3.7 or higher
- Git
- PowerShell (for Windows tools)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/your-username/SysAdminSuite.git
cd SysAdminSuite
```

2. Check the current version:
```bash
python version_manager.py
```

3. Create a new release:
```bash
python release_manager.py patch  # for patch release
python release_manager.py minor  # for minor release
python release_manager.py major  # for major release
```

## Version Management

SysAdminSuite uses a centralized version management system:

- **Single Source of Truth**: `version_manager.py` contains the authoritative version
- **Automated Bumping**: Use `release_manager.py` to automatically bump versions
- **Semantic Versioning**: Follows MAJOR.MINOR.PATCH format
- **Git Integration**: Automatic tagging and release creation

### Version Bumping

```bash
# Patch release (bug fixes)
python release_manager.py patch

# Minor release (new features)
python release_manager.py minor

# Major release (breaking changes)
python release_manager.py major
```

## Tool Categories

### Configs
- System configuration templates
- Registry modifications
- Environment setup scripts
- Security configurations

### Installs
- Software installation automation
- Package management scripts
- Dependency installation tools
- Silent installation configurations

### Printer Mapping
- Network printer configuration
- Driver installation scripts
- Print server management
- Printer discovery tools

### Remote Solutions
- Remote desktop tools
- SSH configuration
- VPN setup scripts
- Remote management utilities

### Tests
- System validation tools
- Performance testing scripts
- Security assessment utilities
- Automated testing frameworks

## Development

### Adding New Tools

1. Create your tool in the appropriate category directory
2. Update the version if needed
3. Add documentation
4. Test thoroughly
5. Update the changelog

### Release Process

1. Update version in `version_manager.py`
2. Update `CHANGELOG.md` with new version entry
3. Update this README with new version information
4. Run the release manager
5. Create GitHub release with release notes

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Commit Message Convention

```
type(scope): description

Examples:
feat(printer): add network printer mapping tool
fix(config): resolve Windows registry path issue
docs(readme): update installation instructions
refactor(install): improve software installation process
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of changes.

## Support

For issues and questions:
- Create an issue on GitHub
- Check the documentation
- Review the changelog

## Roadmap

- [ ] Additional automation tools
- [ ] Enhanced security features
- [ ] Cloud integration tools
- [ ] Advanced monitoring capabilities
- [ ] Container management tools
