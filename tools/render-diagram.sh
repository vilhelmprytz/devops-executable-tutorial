#!/usr/bin/env bash
# Render the architecture SVG to the PNG the scenario embeds (Killercoda has no
# Mermaid, so diagrams ship as images).
set -euo pipefail
cd "$(dirname "$0")"
magick -background white -density 150 diagram.svg \
  -resize 1000x ../detection-as-code-with-falco/assets/architecture.png
echo "wrote assets/architecture.png"
