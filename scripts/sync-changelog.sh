#!/usr/bin/env bash
# Derive version / release notes / debian/changelog from top-level CHANGELOG.
#
# Usage:
#   scripts/sync-changelog.sh version   # print latest semver (e.g. 0.1.0)
#   scripts/sync-changelog.sh notes     # print notes body for latest
#   scripts/sync-changelog.sh debian    # write debian/changelog from CHANGELOG
#
# GitHub Actions runs this after a tag. AGENTS ARE BANNED from running it.
# Do not rewrite debian/changelog, unset CURSOR_AGENT, spoof the environment,
# or otherwise work around this guard. Only CI or the human in a normal
# terminal runs scripts/sync-changelog.sh.
set -euo pipefail

if [[ "${CURSOR_AGENT:-}" == "1" ]]; then
	cat >&2 <<'EOF'
error: agents are banned from running scripts/sync-changelog.sh.

Do not work around this (unset CURSOR_AGENT, fake the env, write
debian/changelog yourself, etc.). GitHub Actions syncs debian/changelog
from CHANGELOG after the tag; the human may run this in a normal terminal.
EOF
	exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
changelog="${root}/CHANGELOG"
pkg_name="ibus-sherpa-onnx"
maintainer="Alan Knowles <alan@roojs.com>"

if [[ ! -f "${changelog}" ]]; then
	echo "missing ${changelog}" >&2
	exit 1
fi

cmd="${1:-}"

latest_header() {
	# First "## X.Y.Z" or "## X.Y.Z - date" line
	grep -E '^## [0-9]+\.[0-9]+\.[0-9]+' "${changelog}" | head -1
}

latest_version() {
	local h
	h="$(latest_header)"
	if [[ -z "${h}" ]]; then
		echo "no ## X.Y.Z heading in CHANGELOG" >&2
		exit 1
	fi
	sed -E 's/^## ([0-9]+\.[0-9]+\.[0-9]+).*/\1/' <<<"${h}"
}

latest_date() {
	local h rest
	h="$(latest_header)"
	rest="$(sed -E 's/^## [0-9]+\.[0-9]+\.[0-9]+[[:space:]]*([-–—][[:space:]]*)?//' <<<"${h}")"
	if [[ "${rest}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
		echo "${rest}"
		return
	fi
	date -u +%Y-%m-%d
}

latest_notes() {
	awk '
		BEGIN { take=0 }
		/^## [0-9]+\.[0-9]+\.[0-9]+/ {
			if (take) exit
			take=1
			next
		}
		take && /^## / { exit }
		take { print }
	' "${changelog}" | sed -e 's/^[[:space:]]*$//' | sed -e '/./,$!d'
}

case "${cmd}" in
version)
	latest_version
	;;
notes)
	latest_notes
	;;
debian)
	ver="$(latest_version)"
	day="$(latest_date)"
	# RFC2822-ish date for debian/changelog (local TZ)
	rfc_date="$(date -d "${day}" '+%a, %d %b %Y %H:%M:%S %z' 2>/dev/null \
		|| date '+%a, %d %b %Y %H:%M:%S %z')"
	{
		echo "${pkg_name} (${ver}-1) unstable; urgency=medium"
		echo
		while IFS= read -r line; do
			if [[ -z "${line}" ]]; then
				echo
				continue
			fi
			if [[ "${line}" == -* || "${line}" == \** ]]; then
				line="${line#- }"
				line="${line#\* }"
				echo "  * ${line}"
			else
				# wrapped continuation of previous bullet
				echo "    ${line}"
			fi
		done < <(latest_notes)
		echo
		echo " -- ${maintainer}  ${rfc_date}"
	} >"${root}/debian/changelog"
	echo "wrote debian/changelog for ${ver}-1"
	;;
*)
	echo "usage: $0 {version|notes|debian}" >&2
	exit 2
	;;
esac
