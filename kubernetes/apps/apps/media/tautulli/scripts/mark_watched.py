#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Description:  Automatically mark a video (movie, show, season, or episode)
#               as played in Plex for specific users.
# Author:       /u/SwiftPanda16
# Requires:     plexapi
#
# Tautulli script trigger:
#    * Notify on watched
# Tautulli script conditions:
#    * Condition {1}:
#        [ Username | is | <from username> ]
#    * Condition {2} (optional):
#        [ Library Name | is | DVR ]
# Tautulli script arguments:
#    * Watched:
#        --rating_key {rating_key} --users "<to username2>" "<to username3>"

import argparse
import os
from plexapi.server import PlexServer
from plexapi.video import Video

# Environmental Variables
PLEX_URL = os.getenv("PLEX_URL")
PLEX_TOKEN = os.getenv("PLEX_TOKEN")


def validate_config():
    missing = []
    if not PLEX_URL:
        missing.append("PLEX_URL")
    if not PLEX_TOKEN:
        missing.append("PLEX_TOKEN")

    if missing:
        raise SystemExit(
            f"Missing required environment variables: {', '.join(missing)}"
        )


def mark_watched(plex: PlexServer, rating_key: int, users: list[str]) -> None:
    """Mark a Plex item as watched for the provided users."""
    admin = plex.myPlexAccount().username.lower()
    for user in users:
        server = plex if user.lower() == admin else plex.switchUser(user)
        item = server.fetchItem(rating_key)
        if isinstance(item, Video):
            print(f"Marking {item.title} as watched for {user}.")
            item.markWatched()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rating_key", required=True, type=int)
    parser.add_argument("--users", required=True, nargs="+")
    args = parser.parse_args()

    validate_config()
    plex = PlexServer(PLEX_URL, PLEX_TOKEN)
    mark_watched(plex, **vars(args))


if __name__ == "__main__":
    main()
