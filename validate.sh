#!/bin/bash
# Top-level validation script
# Run this whenever you add or modify project files
# Add more validation commands here as needed

set -e

echo "==================================="
echo "Running Project Validations"
echo "==================================="
echo ""

# Validate level JSON files
echo "→ Validating level JSON files..."
swift app/scripts/validate_levels.swift

echo ""
echo "==================================="
echo "✓ All validations passed!"
echo "==================================="
