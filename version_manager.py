#!/usr/bin/env python3
"""
SysAdminSuite Version Manager
Centralized version management for the SysAdminSuite collection
"""
# --- app metadata (authoritative) ---
APP_NAME = "SysAdminSuite"
VERSION = "1.0.0"          # <— semver, no leading "v"
# ------------------------------------

import os
import re
import json
from pathlib import Path
from typing import Dict, List, Optional, Tuple

class VersionManager:
    """Manages version information across SysAdminSuite components"""
    
    def __init__(self, project_root: Optional[str] = None):
        self.project_root = Path(project_root) if project_root else Path(__file__).parent
        self.version_file = self.project_root / "VERSION.json"
        self.changelog_file = self.project_root / "CHANGELOG.md"
        
    def get_current_version(self) -> str:
        """Get the current version from the authoritative source"""
        return VERSION
    
    def get_version_info(self) -> Dict[str, str]:
        """Get comprehensive version information"""
        return {
            "version": self.get_current_version(),
            "app_name": APP_NAME,
            "version_file": str(self.version_file),
            "changelog_file": str(self.changelog_file)
        }
    
    def update_version_in_file(self, file_path: str, new_version: str) -> bool:
        """Update version in a specific file"""
        try:
            file_path = Path(file_path)
            if not file_path.exists():
                return False
                
            content = file_path.read_text(encoding='utf-8')
            
            # Pattern to match VERSION = "X.Y.Z" or __version__ = "X.Y.Z"
            pattern = r'(?m)^(?:__version__|VERSION)\s*=\s*["\']\d+\.\d+\.\d+["\']'
            replacement = f'VERSION = "{new_version}"'
            
            if re.search(pattern, content):
                updated_content = re.sub(pattern, replacement, content)
                file_path.write_text(updated_content, encoding='utf-8')
                return True
                
        except Exception as e:
            print(f"Error updating version in {file_path}: {e}")
            return False
            
        return False
    
    def update_all_version_files(self, new_version: str) -> List[str]:
        """Update version in all relevant files"""
        updated_files = []
        
        # Files that typically contain version information
        version_files = [
            "version_manager.py",
            "main.py",
            "setup.py",
            "pyproject.toml",
            "package.json"
        ]
        
        for file_name in version_files:
            file_path = self.project_root / file_name
            if file_path.exists() and self.update_version_in_file(str(file_path), new_version):
                updated_files.append(file_name)
                
        return updated_files
    
    def bump_version(self, bump_type: str = "patch") -> str:
        """Bump version according to semantic versioning"""
        current = self.get_current_version()
        major, minor, patch = map(int, current.split('.'))
        
        if bump_type == "major":
            major += 1
            minor = 0
            patch = 0
        elif bump_type == "minor":
            minor += 1
            patch = 0
        elif bump_type == "patch":
            patch += 1
        else:
            raise ValueError(f"Invalid bump type: {bump_type}")
            
        new_version = f"{major}.{minor}.{patch}"
        return new_version
    
    def create_version_entry(self, version: str, changes: Dict[str, List[str]]) -> str:
        """Create a changelog entry for a new version"""
        entry = f"\n## [{version}] - {self._get_current_date()}\n\n"
        
        for change_type, items in changes.items():
            if items:
                entry += f"### {change_type.title()}\n"
                for item in items:
                    entry += f"- {item}\n"
                entry += "\n"
                
        return entry
    
    def _get_current_date(self) -> str:
        """Get current date in YYYY-MM-DD format"""
        from datetime import datetime
        return datetime.now().strftime("%Y-%m-%d")
    
    def validate_version_format(self, version: str) -> bool:
        """Validate that version follows semantic versioning"""
        pattern = r'^\d+\.\d+\.\d+$'
        return bool(re.match(pattern, version))

if __name__ == "__main__":
    # Example usage
    vm = VersionManager()
    print(f"Current version: {vm.get_current_version()}")
    print(f"Version info: {vm.get_version_info()}")
