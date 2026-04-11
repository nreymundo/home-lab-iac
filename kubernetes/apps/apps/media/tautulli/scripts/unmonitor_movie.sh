#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 ttIMDBID" >&2
}

die() {
    echo "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_env() {
    [ -n "$${!1:-}" ] || die "Missing required environment variable: $$1"
}

radarr_get() {
    curl -fsS -H "X-Api-Key: $$RADARR_API_KEY" "$$1"
}

radarr_put() {
    curl -fsS -X PUT \
        -H "X-Api-Key: $$RADARR_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$1" \
        "$2"
}

# Check if an IMDb ID was provided
if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

require_env "RADARR_URL"
require_env "RADARR_API_KEY"
require_command "curl"
require_command "jq"

IMDB_ID="$1"

# Ensure the IMDb ID starts with 'tt'
if [[ "$$IMDB_ID" != tt* ]]; then
    IMDB_ID="tt$$IMDB_ID"
fi

# Step 1: Retrieve all movies from Radarr
if ! MOVIES_JSON=$(radarr_get "$$RADARR_URL/api/v3/movie"); then
    die "Failed to retrieve movies from Radarr."
fi

# Step 2: Find the movie ID based on the IMDb ID
if ! MOVIE_ID=$(printf '%s' "$$MOVIES_JSON" | jq -er --arg IMDB_ID "$$IMDB_ID" 'first(.[] | select(.imdbId == $$IMDB_ID) | .id) // empty'); then
    echo "Movie with IMDb ID '$$IMDB_ID' not found in Radarr."
    exit 1
fi

echo "Found movie with IMDb ID '$$IMDB_ID' and Radarr ID $$MOVIE_ID."

# Step 3: Retrieve the current movie object
if ! MOVIE_JSON=$(radarr_get "$$RADARR_URL/api/v3/movie/$$MOVIE_ID"); then
    die "Failed to retrieve movie details for Radarr ID $$MOVIE_ID."
fi

# Step 4: Modify the 'monitored' property to false in memory
if ! UPDATED_MOVIE_JSON=$(printf '%s' "$$MOVIE_JSON" | jq '.monitored = false'); then
    die "Failed to prepare updated movie payload."
fi

# Step 5: Update the movie in Radarr
if ! RESPONSE=$(radarr_put "$$UPDATED_MOVIE_JSON" "$$RADARR_URL/api/v3/movie/$$MOVIE_ID"); then
    die "Failed to update movie in Radarr."
fi

if printf '%s' "$$RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
    echo "Movie with IMDb ID '$$IMDB_ID' has been marked as not monitored."
else
    echo "Failed to update movie. Response from Radarr:" >&2
    printf '%s\n' "$$RESPONSE" >&2
    exit 1
fi
