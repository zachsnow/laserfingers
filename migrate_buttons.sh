#!/bin/bash
# Migrates button "position" to "endpoint" format in all level JSON files

find app/Laserfingers/Levels -name "*.json" -type f | while read -r file; do
    echo "Processing: $file"
    # Use Python to do the JSON transformation
    python3 - <<'PYTHON' "$file"
import json
import sys

filename = sys.argv[1]

with open(filename, 'r') as f:
    data = json.load(f)

# Transform buttons if they exist
if 'buttons' in data:
    for button in data['buttons']:
        if 'position' in button and 'endpoint' not in button:
            pos = button['position']
            button['endpoint'] = {
                'points': [pos],
                'cycleSeconds': None,
                't': 0
            }
            del button['position']

# Write back
with open(filename, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')

print(f"Updated: {filename}")
PYTHON
done

echo "Migration complete!"
