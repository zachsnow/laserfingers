#!/usr/bin/env python3
"""
Convert laser level JSON files from old format to new format.

Old format uses:
- sweeper: Ray with moving endpoint (perpendicular to path)
- rotor: Ray with stationary endpoint + rotation
- segment: Segment with stationary endpoints

New format uses:
- RayLaser: single endpoint (stationary or moving), angle, rotation speed
- SegmentLaser: two endpoints (each stationary or moving)
"""

import json
import os
import sys
import math
from pathlib import Path


def convert_sweeper_to_ray(sweeper_data):
    """Convert old sweeper format to new Ray laser format."""
    start = sweeper_data["start"]
    end = sweeper_data["end"]
    sweep_seconds = sweeper_data["sweepSeconds"]

    # Calculate angle perpendicular to sweep path
    dx = end["x"] - start["x"]
    dy = end["y"] - start["y"]
    angle_radians = math.atan2(dy, dx) + (math.pi / 2)

    # Create endpoint path (moving between start and end)
    # cycleSeconds is full round-trip, so double the one-way sweep time
    endpoint_path = {
        "points": [start, end],
        "cycleSeconds": sweep_seconds * 2,
        "initialT": 0.0
    }

    return {
        "type": "ray",
        "endpoint": endpoint_path,
        "initialAngle": angle_radians,
        "rotationSpeed": 0.0
    }


def convert_rotor_to_ray(rotor_data):
    """Convert old rotor format to new Ray laser format."""
    center = rotor_data["center"]
    speed_deg_per_sec = rotor_data["speedDegreesPerSecond"]
    initial_angle_deg = rotor_data["initialAngleDegrees"]

    # Convert degrees to radians
    initial_angle_rad = initial_angle_deg * math.pi / 180
    rotation_speed_rad = speed_deg_per_sec * math.pi / 180

    # Create stationary endpoint path
    endpoint_path = {
        "points": [center],
        "cycleSeconds": None,
        "initialT": 0.0
    }

    return {
        "type": "ray",
        "endpoint": endpoint_path,
        "initialAngle": initial_angle_rad,
        "rotationSpeed": rotation_speed_rad
    }


def convert_segment_to_segment(segment_data):
    """Convert old segment format to new Segment laser format."""
    start = segment_data["start"]
    end = segment_data["end"]

    # Create stationary endpoint paths
    start_path = {
        "points": [start],
        "cycleSeconds": None,
        "initialT": 0.0
    }

    end_path = {
        "points": [end],
        "cycleSeconds": None,
        "initialT": 0.0
    }

    return {
        "type": "segment",
        "startEndpoint": start_path,
        "endEndpoint": end_path
    }


def convert_laser(old_laser):
    """Convert a single laser from old format to new format."""
    laser_id = old_laser["id"]
    color = old_laser["color"]
    thickness = old_laser["thickness"]
    cadence = old_laser.get("cadence")

    kind = old_laser["kind"]
    kind_type = kind["type"]

    # Convert based on type
    if kind_type == "sweeper":
        new_kind = convert_sweeper_to_ray(kind["sweeper"])
    elif kind_type == "rotor":
        new_kind = convert_rotor_to_ray(kind["rotor"])
    elif kind_type == "segment":
        new_kind = convert_segment_to_segment(kind["segment"])
    else:
        raise ValueError(f"Unknown laser kind: {kind_type}")

    # Build new laser format
    new_laser = {
        "id": laser_id,
        "color": color,
        "thickness": thickness,
        "enabled": old_laser.get("enabled", True),
        **new_kind
    }

    if cadence is not None:
        new_laser["cadence"] = cadence

    return new_laser


def convert_level_file(filepath):
    """Convert a single level file in place."""
    print(f"Converting {filepath}...")

    with open(filepath, 'r') as f:
        level = json.load(f)

    # Convert all lasers
    if "lasers" in level:
        level["lasers"] = [convert_laser(laser) for laser in level["lasers"]]

    # Write back with nice formatting
    with open(filepath, 'w') as f:
        json.dump(level, f, indent=2)
        f.write('\n')  # Add trailing newline


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
            convert_level_file(filepath)
        except Exception as e:
            print(f"Error converting {filepath}: {e}")
            sys.exit(1)

    print(f"\nSuccessfully converted {len(json_files)} level files")


if __name__ == "__main__":
    main()
