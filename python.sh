#!/usr/bin/env bash

export USER_ID="$(id -u)"
export GROUP=$(id -gn)
export GROUP_ID=$(id -g)
export PWD="$(pwd)"

if [[ -z "$*" ]]; then
  docker-compose run --rm -v "$HOME:$HOME" -v "$PWD:$PWD" -w "$PWD" --user "$USER" -e PATH python
else
  docker-compose run --rm -v "$HOME:$HOME" -v "$PWD:$PWD" -w "$PWD" --user "$USER" python "$@"
fi