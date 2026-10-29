#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/USB Mirror.app"
[[ -d "$APP" ]] || ./build.command
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/usbmirror-package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/root/Applications" "$PWD/dist"
ditto --norsrc --noextattr --noqtn "$APP" "$STAGING/root/Applications/USB Mirror.app"
# Disable relocation so an existing copy elsewhere cannot redirect installation.
cat > "$STAGING/components.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><array><dict>
<key>RootRelativeBundlePath</key><string>Applications/USB Mirror.app</string>
<key>BundleIsRelocatable</key><false/>
<key>BundleIsVersionChecked</key><true/>
<key>BundleHasStrictIdentifier</key><true/>
<key>BundleOverwriteAction</key><string>upgrade</string>
</dict></array></plist>
PLIST
pkgbuild --root "$STAGING/root" --component-plist "$STAGING/components.plist" \
  --identifier local.usbmirror.mac.pkg --version "$VERSION" --install-location / \
  --ownership recommended "$STAGING/USBMirror-component.pkg"
cat > "$STAGING/Distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>USB Mirror $VERSION</title>
  <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
  <domains enable_localSystem="true" enable_currentUserHome="false" enable_anywhere="false"/>
  <volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
  <choices-outline><line choice="usbmirror"/></choices-outline>
  <choice id="usbmirror" visible="false" title="USB Mirror">
    <pkg-ref id="local.usbmirror.mac.pkg"/>
  </choice>
  <pkg-ref id="local.usbmirror.mac.pkg" version="$VERSION" onConclusion="none">USBMirror-component.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$STAGING/Distribution.xml" --package-path "$STAGING" \
  "$PWD/dist/USB-Mirror-v${VERSION}-macOS-AppleSilicon.pkg"
echo "Installer ready in $PWD/dist (unsigned; not notarized)."
