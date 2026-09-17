APP_RESOURCES = app/Sources/Minutes/Resources

.PHONY: sync-app-resources test test-ui run package

# Build a proper .app bundle, ad-hoc sign it, and launch
run:
	cd app && swift build
	@mkdir -p app/.build/Minutes.app/Contents/MacOS
	@mkdir -p app/.build/Minutes.app/Contents/Resources
	cp app/.build/debug/Minutes app/.build/Minutes.app/Contents/MacOS/
	sed -e "s/__APP_VERSION__/dev/g" -e "s/__APP_BUILD__/1/g" app/Sources/Minutes/Info.plist > app/.build/Minutes.app/Contents/Info.plist
	@cp -r app/.build/debug/Minutes_Minutes.bundle app/.build/Minutes.app/Contents/Resources/ 2>/dev/null || true
	codesign --force --deep --sign - app/.build/Minutes.app
	open app/.build/Minutes.app

# Build dist/Minutes.app, dist/Minutes-macos-arm64.dmg, and dist/Minutes-macos-arm64.zip.
# By default this embeds a relocatable Python environment and dependencies.
package:
	scripts/package-macos.sh

sync-app-resources:
	cp transcribe.py   $(APP_RESOURCES)/transcribe.py
	cp pyproject.toml  $(APP_RESOURCES)/pyproject.toml
	cp uv.lock         $(APP_RESOURCES)/uv.lock
	@echo "✅ App resources synced"

# Run unit tests (no Xcode required, CI-friendly)
test:
	cd app && swift test --filter MinutesTests

# Run UI tests — requires opening app/Package.swift in Xcode first, then ⌘U
# xcodebuild cannot produce a .app bundle from a Swift Package without Xcode's scheme
test-ui:
	@echo "ℹ️  Open app/Package.swift in Xcode and press ⌘U to run UI tests"
