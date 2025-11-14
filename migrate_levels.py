#!/usr/bin/env python3
"""
Migration script to update level JSON files to use endpoints array format.

Changes:
- Button: endpoint -> endpoints: [endpoint]
- RayLaser (sweeper/rotor): endpoint -> endpoints: [endpoint]
- SegmentLaser: {startEndpoint, endEndpoint} -> endpoints: [startEndpoint, endEndpoint]
"""

import json
import os
import sys
from pathlib import Path


def migrate_button(button):
    """Migrate button from endpoint to endpoints array."""
    if "endpoint" in button and "endpoints" not in button:
        button["endpoints"] = [button["endpoint"]]
        del button["endpoint"]
    return button


def migrate_laser(laser):
    """Migrate laser to use endpoints array."""
    laser_type = laser.get("type")

    if laser_type in ["sweeper", "rotor"]:
        # Ray lasers: endpoint -> endpoints: [endpoint]
        if "endpoint" in laser and "endpoints" not in laser:
            laser["endpoints"] = [laser["endpoint"]]
            del laser["endpoint"]

    elif laser_type == "segment":
        # Segment lasers: {startEndpoint, endEndpoint} -> endpoints: [start, end]
        if "startEndpoint" in laser and "endEndpoint" in laser and "endpoints" not in laser:
            laser["endpoints"] = [laser["startEndpoint"], laser["endEndpoint"]]
            del laser["startEndpoint"]
            del laser["endEndpoint"]

    return laser


def migrate_level(level_data):
    """Migrate a level JSON object."""
    # Migrate buttons
    if "buttons" in level_data:
        level_data["buttons"] = [migrate_button(button) for button in level_data["buttons"]]

    # Migrate lasers
    if "lasers" in level_data:
        level_data["lasers"] = [migrate_laser(laser) for laser in level_data["lasers"]]

    return level_data


def migrate_file(file_path):
    """Migrate a single JSON file."""
    print(f"Migrating: {file_path}")

    try:
        with open(file_path, 'r') as f:
            data = json.load(f)

        # Check if migration is needed
        needs_migration = False

        if "buttons" in data:
            for button in data["buttons"]:
                if "endpoint" in button:
                    needs_migration = True
                    break

        if not needs_migration and "lasers" in data:
            for laser in data["lasers"]:
                if "endpoint" in laser or "startEndpoint" in laser:
                    needs_migration = True
                    break

        if not needs_migration:
            print(f"  ✓ Already migrated, skipping")
            return True

        # Migrate
        migrated_data = migrate_level(data)

        # Write back with same formatting
        with open(file_path, 'w') as f:
            json.dump(migrated_data, f, indent=2)
            f.write('\n')  # Add trailing newline

        print(f"  ✓ Migrated successfully")
        return True

    except Exception as e:
        print(f"  ✗ Error: {e}")
        return False


def main():
    """Find and migrate all level JSON files."""
    levels_dir = Path("app/Laserfingers/Levels")

    if not levels_dir.exists():
        print(f"Error: Levels directory not found: {levels_dir}")
        sys.exit(1)

    # Find all JSON files
    json_files = list(levels_dir.rglob("*.json"))

    if not json_files:
        print("No JSON files found")
        sys.exit(0)

    print(f"Found {len(json_files)} level files\n")

    success_count = 0
    error_count = 0

    for json_file in sorted(json_files):
        if migrate_file(json_file):
            success_count += 1
        else:
            error_count += 1

    print(f"\nMigration complete:")
    print(f"  ✓ Success: {success_count}")
    if error_count > 0:
        print(f"  ✗ Errors: {error_count}")
        sys.exit(1)


if __name__ == "__main__":
    main()
