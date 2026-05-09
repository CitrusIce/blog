#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s <slug> [--title "Title"] [--category "cat"] [--from /path/to/file.md]\n' "$0" >&2
}

if [ "$#" -lt 1 ]; then
  usage
  exit 1
fi

slug="$1"
shift

title=""
category=""
source_file=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --title)
      [ "$#" -ge 2 ] || { usage; exit 1; }
      title="$2"
      shift 2
      ;;
    --category)
      [ "$#" -ge 2 ] || { usage; exit 1; }
      category="$2"
      shift 2
      ;;
    --from)
      [ "$#" -ge 2 ] || { usage; exit 1; }
      source_file="$2"
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

date_prefix="$(date '+%Y-%m-%d')"
timestamp="$(date '+%Y-%m-%d %H:%M:%S +0800')"
post_path="_posts/${date_prefix}-${slug}.markdown"

if [ -e "$post_path" ]; then
  printf 'Post already exists: %s\n' "$post_path" >&2
  exit 1
fi

if [ -n "$source_file" ] && [ ! -f "$source_file" ]; then
  printf 'Source file not found: %s\n' "$source_file" >&2
  exit 1
fi

{
  printf '%s\n' '---'
  printf '%s\n' 'layout: post'
  printf 'title: "%s"\n' "$title"
  printf 'date: %s\n' "$timestamp"
  printf 'categories: %s\n' "$category"
  printf '%s\n\n' '---'

  if [ -n "$source_file" ]; then
    cat "$source_file"
    printf '\n'
  fi
} > "$post_path"

printf 'Created %s\n' "$post_path"
