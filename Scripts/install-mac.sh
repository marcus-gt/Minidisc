#!/bin/sh
# Builds the Mac app (Release, signed with your Apple Development certificate) and installs it as
# /Applications/mækster.app, replacing the copy that's there. Run it again after each update.

set -eu

usage() {
    cat <<'EOF'
Usage: ./Scripts/install-mac.sh [--no-open]

Archives the Maekster scheme for macOS, checks the signature, quits a running
mækster (so it saves the playback session), installs the app in /Applications
and opens it.

  --no-open  Install without opening the app.
  -h, --help Show this help.

Set MAEKSTER_INSTALL_DIR to install somewhere other than /Applications.
EOF
}

open_after=true
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-open) open_after=false ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
    shift
done

cd "$(dirname "$0")/.."

bundle_id=io.github.marcus-gt.maekster
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/maekster-install.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT
archive="$work_dir/Maekster.xcarchive"
destination="${MAEKSTER_INSTALL_DIR:-/Applications}/mækster.app"

echo "Building (Release, macOS)…"
# -allowProvisioningUpdates lets Xcode fetch the development profile the Keychain entitlement needs.
if ! xcodebuild archive \
    -project maekster.xcodeproj \
    -scheme Maekster \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive" \
    -allowProvisioningUpdates \
    >"$work_dir/build.log" 2>&1; then
    echo "Build failed. Last lines of the log:" >&2
    tail -n 40 "$work_dir/build.log" >&2
    exit 1
fi

app="$archive/Products/Applications/Maekster.app"
codesign --verify --deep --strict "$app"

# Quit a running copy the normal way, so it saves the playback position first.
if pgrep -qf "mækster.app/Contents/MacOS/Maekster|Maekster.app/Contents/MacOS/Maekster"; then
    echo "Quitting the running mækster…"
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    tries=0
    while pgrep -qf "mækster.app/Contents/MacOS/Maekster|Maekster.app/Contents/MacOS/Maekster" && [ "$tries" -lt 20 ]; do
        sleep 0.5
        tries=$((tries + 1))
    done
fi

echo "Installing $destination…"
rm -rf "$destination"
ditto "$app" "$destination"

version=$(defaults read "$destination/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
build=$(defaults read "$destination/Contents/Info" CFBundleVersion 2>/dev/null || echo "?")
echo "Installed mækster $version ($build)."

if [ "$open_after" = true ]; then
    open "$destination"
fi
