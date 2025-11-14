#!/usr/bin/env python3
"""
Rename initialT to t in all endpoint paths and remove if 0.
"""

import json
import sys
from pathlib import Path


def process_endpoint(endpoint):
    """Rename initialT to t, remove if 0."""
    if "initialT" in endpoint:
        value = endpoint["initialT"]
        del endpoint["initialT"]
        if value != 0.0:
            endpoint["t"] = value


def process_laser(laser):
    """Process all endpoints in a laser."""
    if laser.get("type") == "ray" and "endpoint" in laser:
        process_endpoint(laser["endpoint"])
    elif laser.get("type") == "segment":
        if "startEndpoint" in laser:
            process_endpoint(laser["startEndpoint"])
        if "endEndpoint" in laser:
            process_endpoint(laser["endEndpoint"])


def process_level_file(filepath):
    """Process a single level file."""
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
