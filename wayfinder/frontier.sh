#!/bin/sh
# The wayfinder frontier: open, unassigned tickets whose blockers are all closed.
# Runs from anywhere; paths resolve against the repository root.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dir="$root/wayfinder/tickets"

field() { sed -n "s/^$2: *//p" "$1" | head -1; }

closed=""
for f in "$dir"/*.md; do
  [ -e "$f" ] || continue
  if [ "$(field "$f" status)" = "closed" ]; then
    closed="$closed $(field "$f" id)"
  fi
done

for f in "$dir"/*.md; do
  [ -e "$f" ] || continue
  [ "$(field "$f" status)" = "open" ] || continue
  [ -z "$(field "$f" assignee)" ] || continue
  blocked=0
  for b in $(field "$f" blocked_by | tr -d '[]' | tr ',' ' '); do
    case " $closed " in
      *" $b "*) ;;
      *) blocked=1 ;;
    esac
  done
  [ "$blocked" = 0 ] || continue
  printf '%s  %s\n' "$(field "$f" id)" "$(field "$f" title)"
done
