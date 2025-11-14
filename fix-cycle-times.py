#!/usr/bin/env python3
"""
Fix cycle times in already-converted levels.
Double the cycleSeconds for all moving endpoints to account for round-trip.
"""

import json
import sys
from pathlib import Path


def fix_laser(laser):
    """Fix cycleSeconds in a laser's endpoints."""
    if laser.get("type") == "ray" and "endpoint" in laser:
        endpoint = laser["endpoint"]
        if endpoint.get("cycleSeconds") is not None:
            endpoint["cycleSeconds"] *= 2

    elif laser.get("type") == "segment":
        for endpoint_key in ["startEndpoint", "endEndpoint"]:
            if endpoint_key in laser:
                endpoint = laser[endpoint_key]
                if endpoint.get("cycleSeconds") is not None:
                    endpoint["cycleSeconds"] *= 2


def fix_level_file(filepath):
    """Fix cycle times in a single level file."""
    print(f"Fixing {filepath}...")

    with open(filepath, 'r') as f:
        level = json.load(f)

    # Fix all lasers
    if "lasers" in level:
        for laser in level["lasers"]:
            fix_laser(laser)

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
            fix_level_file(filepath)
        except Exception as e:
            print(f"Error fixing {filepath}: {e}")
            import traceback
            traceback.print_exc()
            sys.exit(1)

    print(f"\nSuccessfully fixed {len(json_files)} level files")


if __name__ == "__main__":
    main()
