#!/usr/bin/env python3
"""
SysAdminSuite Release Manager
Python-based release management for the SysAdminSuite collection
"""

import os
import sys
import re
import subprocess
from pathlib import Path
from typing import Optional, Tuple

class ReleaseManager:
    """Manages releases for SysAdminSuite"""
    
    def __init__(self, project_root: Optional[str] = None):
        self.project_root = Path(project_root) if project_root else Path(__file__).parent
        self.version_file = self.project_root / "version_manager.py"
        
    def get_current_version(self) -> str:
        """Get current version from version_manager.py"""
        if not self.version_file.exists():
            raise FileNotFoundError(f"Version file not found: {self.version_file}")
            
        content = self.version_file.read_text(encoding='utf-8')
        match = re.search(r'VERSION\s*=\s*["\'](\d+\.\d+\.\d+)["\']', content)
        if not match:
            raise ValueError("Could not find VERSION in version_manager.py")
            
        return match.group(1)
    
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
    
    def update_version_file(self, new_version: str) -> bool:
        """Update version in version_manager.py"""
        try:
            content = self.version_file.read_text(encoding='utf-8')
            updated_content = re.sub(
                r'VERSION\s*=\s*["\']\d+\.\d+\.\d+["\']',
                f'VERSION = "{new_version}"',
                content
            )
            self.version_file.write_text(updated_content, encoding='utf-8')
            return True
        except Exception as e:
            print(f"Error updating version file: {e}")
            return False
    
    def run_git_command(self, command: list) -> Tuple[bool, str]:
        """Run a git command and return success status and output"""
        try:
            result = subprocess.run(
                command,
                cwd=self.project_root,
                capture_output=True,
                text=True,
                check=True
            )
            return True, result.stdout
        except subprocess.CalledProcessError as e:
            return False, e.stderr
    
    def create_release(self, bump_type: str = "patch", push: bool = True) -> bool:
        """Create a new release"""
        try:
            print(f"Current version: {self.get_current_version()}")
            
            # Bump version
            new_version = self.bump_version(bump_type)
            tag_version = f"v{new_version}"
            print(f"New version: {new_version}")
            
            # Update version file
            if not self.update_version_file(new_version):
                print("Failed to update version file")
                return False
            
            # Git operations
            success, output = self.run_git_command(["add", "version_manager.py"])
            if not success:
                print(f"Failed to add version file: {output}")
                return False
            
            success, output = self.run_git_command([
                "commit", "-m", f"chore(version): bump to {tag_version}"
            ])
            if not success:
                print(f"Failed to commit: {output}")
                return False
            
            success, output = self.run_git_command([
                "tag", "-a", tag_version, "-m", f"Release {tag_version}: SysAdminSuite IT tools collection"
            ])
            if not success:
                print(f"Failed to create tag: {output}")
                return False
            
            if push:
                success, output = self.run_git_command(["push", "origin", "main"])
                if not success:
                    print(f"Failed to push to main: {output}")
                    return False
                
                success, output = self.run_git_command(["push", "origin", tag_version])
                if not success:
                    print(f"Failed to push tag: {output}")
                    return False
            
            print(f"Release {tag_version} created successfully!")
            return True
            
        except Exception as e:
            print(f"Error creating release: {e}")
            return False

def main():
    """Main function for command line usage"""
    import argparse
    
    parser = argparse.ArgumentParser(description="SysAdminSuite Release Manager")
    parser.add_argument(
        "bump_type",
        choices=["patch", "minor", "major"],
        default="patch",
        nargs="?",
        help="Type of version bump (default: patch)"
    )
    parser.add_argument(
        "--no-push",
        action="store_true",
        help="Don't push changes to remote"
    )
    
    args = parser.parse_args()
    
    manager = ReleaseManager()
    
    if manager.create_release(args.bump_type, not args.no_push):
        print("Release completed successfully!")
        sys.exit(0)
    else:
        print("Release failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
