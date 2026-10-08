#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"
app="$dist/HAR Lens.app"
archive="$dist/HAR-Lens-macOS.zip"
bundle_id="com.marvix.harlens"

mkdir -p "$dist"
staging="$(mktemp -d "${TMPDIR:-/tmp}/har-lens-build.XXXXXX")"
cleanup() {
    if [[ -d "$staging/previous.app" && ! -e "$app" && ! -L "$app" ]]; then
        mv "$staging/previous.app" "$app" || return
    fi
    rm -rf "$staging"
}
trap cleanup EXIT

if [[ -e "$app" || -L "$app" ]]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)"
    if [[ ! -d "$app" || -L "$app" || "$existing_id" != "$bundle_id" ]]; then
        printf 'Отказ от замены чужого файла: %s\n' "$app" >&2
        exit 1
    fi
fi
if [[ -e "$archive" || -L "$archive" ]]; then
    if [[ ! -f "$archive" || -L "$archive" ]]; then
        printf 'Отказ от замены чужого файла: %s\n' "$archive" >&2
        exit 1
    fi
fi

export CLANG_MODULE_CACHE_PATH="$staging/clang-cache"
export SWIFT_MODULECACHE_PATH="$staging/swift-cache"
for arch in arm64 x86_64; do
    build_options=(--package-path "$root" --scratch-path "$staging/build-$arch" --cache-path "$staging/package-cache" --disable-sandbox --build-system native --configuration release --product HARLens --triple "$arch-apple-macosx13.0")
    swift build "${build_options[@]}"
    bin_dir="$(swift build "${build_options[@]}" --show-bin-path)"
    cp -X "$bin_dir/HARLens" "$staging/HARLens-$arch"
    minimum="$(/usr/bin/otool -l "$staging/HARLens-$arch" | awk '/minos/ {print $2}')"
    if [[ "$minimum" != "13.0" ]]; then
        printf 'Неверная минимальная версия macOS для %s: %s\n' "$arch" "$minimum" >&2
        exit 1
    fi
done

staged_app="$staging/HAR Lens.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
/usr/bin/lipo -create "$staging/HARLens-arm64" "$staging/HARLens-x86_64" -output "$staged_app/Contents/MacOS/HARLens"
for arch in arm64 x86_64; do
    /usr/bin/lipo "$staged_app/Contents/MacOS/HARLens" -verify_arch "$arch"
done
cp -X "$root/Resources/Info.plist" "$staged_app/Contents/Info.plist"
/usr/bin/plutil -lint "$staged_app/Contents/Info.plist"
swift -module-cache-path "$staging/clang-cache" "$root/scripts/make-icon.swift" "$staged_app/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --sign - "$staged_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$staged_app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$staged_app" "$staging/HAR-Lens-macOS.zip"

if [[ -d "$app" ]]; then
    mv "$app" "$staging/previous.app"
fi
mv "$staged_app" "$app"
for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
    /usr/bin/xattr -rd "$attribute" "$app" 2>/dev/null || true
done
if ! /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"; then
    mv "$app" "$staging/failed.app"
    exit 1
fi
mv -f "$staging/HAR-Lens-macOS.zip" "$archive"
printf 'Готово:\n%s\n%s\n' "$app" "$archive"
