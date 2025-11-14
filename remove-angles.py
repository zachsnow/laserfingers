#!/usr/bin/env python3
"""
Remove initialAngle from all ray lasers in level files.
The angle will now default based on endpoint path.
"""

import json
import sys
from pathlib import Path


def process_laser(laser):
    """Remove initialAngle from ray lasers."""
    if laser.get("type") == "ray" and "initialAngle" in laser:
        del laser["initialAngle"]


def process_level_file(filepath):
    """Remove angles from a single level file."""
    print(f"Processing {filepath}...")

    with open(filepath, 'r') as f:
        level = json.load(f)

    # Process all lasers
    if "lasers" in level:
        for laser in level["lasers"]:
            process_laser(laser)

    # Write back with nice formatting
    with open(filepath, 'w') as f:
        json.dump(level, f, indent=2)
        f.write('\n')


def main():
    levels_dir = Path("app/Laserfingers/Levels")

    if not levels_dir.exists():
        print(f"Error: Levels directory not found at {levels_dir}")
        sys.exit(1)

    # Find all JSON files recursively
    json_files = list(levels_dir.rglob("*.json"))

    if not json_files:
        print("No JSON files found")
        sys.exit(1)

    print(f"Found {len(json_files)} level files")

    for filepath in json_files:
        try:
            process_level_file(filepath)
        except Exception as e:
            print(f"Error processing {filepath}: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)

    print(f"\nSuccessfully processed {len(json_files)} level files")


if __name__ == "__main__":
    main()
