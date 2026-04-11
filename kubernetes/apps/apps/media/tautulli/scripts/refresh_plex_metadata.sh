#!/bin/bash

set -eu

# Script to force refresh metadata of a Plex item

# Usage: ./refresh_metadata.sh <rating_key>

usage() {
    echo "Usage: $0 <rating_key>" >&2
}

# Check if rating key is provided
if [ -z "$${1:-}" ]; then
    usage
    exit 1
fi

if [ -z "$${PLEX_URL:-}" ]; then
    echo "Missing required environment variable: PLEX_URL" >&2
    exit 1
fi

if [ -z "$${PLEX_TOKEN:-}" ]; then
    echo "Missing required environment variable: PLEX_TOKEN" >&2
    exit 1
fi

# Get the rating key from the first argument
RATING_KEY="$1"

# Construct the API endpoint URL
REFRESH_URL="$$PLEX_URL/library/metadata/$$RATING_KEY/refresh?X-Plex-Token=$$PLEX_TOKEN"

# Use curl to send a PUT request to refresh the metadata
if ! RESPONSE=$(curl -sS -o /dev/null -w "%{http_code}" -X PUT "$$REFRESH_URL"); then
    echo "Failed to send refresh request to Plex." >&2
    exit 1
fi

# Check the HTTP response code
if [ "$$RESPONSE" -eq 200 ]; then
    echo "Metadata refresh request sent for item with rating key $$RATING_KEY."
else
    echo "Failed to send refresh request. HTTP response code: $$RESPONSE" >&2
    exit 1
fi
