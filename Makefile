.PHONY: build test coverage lint file-size mockups package sign-package validate-package beta-release developer-id-package notarize-package staple-package notarized-release check-accessibility smoke-app smoke-login-item smoke-live-cdp smoke-expanded-interaction smoke-expanded-fallback smoke-recording-export smoke-multi-session visual-snapshots visual-structure-smoke visual-snapshot-baseline visual-snapshot-compare visual-snapshot-enforce install clean qa

APP_NAME := PlaywrightDashboard
BUNDLE_ID ?= com.neonwatty.PlaywrightDashboard
APP_VERSION ?= 0.1.1
BUILD_NUMBER ?= 1
PKG_DIR := PlaywrightDashboard
BUILD_DIR := $(PKG_DIR)/.build
CONFIGURATION ?= release
BUILD_CONFIG_FLAG := -c $(CONFIGURATION)
SWIFT_BUILD_DIR := $(BUILD_DIR)/$(CONFIGURATION)
INSTALL_DIR := $(HOME)/Applications
APP_BUNDLE := $(INSTALL_DIR)/$(APP_NAME).app
DIST_DIR := dist
PACKAGE_BUNDLE := $(DIST_DIR)/$(APP_NAME).app
PACKAGE_ZIP := $(DIST_DIR)/$(APP_NAME).zip
VISUAL_SNAPSHOT_BASELINE_DIR ?= $(DIST_DIR)/visual-snapshots-baseline
VISUAL_SNAPSHOT_COMPARE_DIR ?= $(DIST_DIR)/visual-snapshots
VISUAL_SNAPSHOT_DIFF_THRESHOLD ?= 0.01
VISUAL_SNAPSHOT_PIXEL_THRESHOLD ?= 2
SWIFT_FORMAT_TAG ?= swift-6.3.1-RELEASE
SWIFT_FORMAT ?= scripts/swift_format_tool.sh

build:
	cd $(PKG_DIR) && swift build $(BUILD_CONFIG_FLAG)

test:
	cd $(PKG_DIR) && swift test

coverage:
	cd $(PKG_DIR) && swift test --enable-code-coverage
	@echo "Coverage JSON: $$(cd $(PKG_DIR) && swift test --show-codecov-path)"

lint:
	SWIFT_FORMAT_TAG=$(SWIFT_FORMAT_TAG) $(SWIFT_FORMAT) lint --recursive $(PKG_DIR)/Sources $(PKG_DIR)/Tests

format:
	SWIFT_FORMAT_TAG=$(SWIFT_FORMAT_TAG) $(SWIFT_FORMAT) format --recursive --in-place $(PKG_DIR)/Sources $(PKG_DIR)/Tests

file-size:
	@OVERSIZED=$$(find $(PKG_DIR)/Sources -name '*.swift' -exec awk 'END { if (NR > 300) print FILENAME ": " NR " lines" }' {} \;); \
	if [ -n "$$OVERSIZED" ]; then \
		echo "Swift files exceeding 300 lines:"; \
		echo "$$OVERSIZED"; \
		exit 1; \
	else \
		echo "All files within 300-line limit"; \
	fi

mockups:
	@test -f native-app.html
	@test -f expanded-session.html
	@for file in native-app.html expanded-session.html; do \
		if ! grep -qi '<html' "$$file" || ! grep -qi '</html>' "$$file"; then \
			echo "$$file is missing html document tags"; \
			exit 1; \
		fi; \
	done
	@echo "Mockup HTML files are present and structurally complete"

$(PACKAGE_BUNDLE): build
	rm -rf $(PACKAGE_BUNDLE)
	mkdir -p $(PACKAGE_BUNDLE)/Contents/MacOS $(PACKAGE_BUNDLE)/Contents/Resources
	cp $(SWIFT_BUILD_DIR)/$(APP_NAME) $(PACKAGE_BUNDLE)/Contents/MacOS/$(APP_NAME)
	chmod +x $(PACKAGE_BUNDLE)/Contents/MacOS/$(APP_NAME)
	scripts/generate_app_icon.swift $(PACKAGE_BUNDLE)/Contents/Resources/AppIcon.icns
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>CFBundleExecutable</key>' \
		'  <string>$(APP_NAME)</string>' \
		'  <key>CFBundleIdentifier</key>' \
		'  <string>$(BUNDLE_ID)</string>' \
		'  <key>CFBundleName</key>' \
		'  <string>$(APP_NAME)</string>' \
		'  <key>CFBundleDisplayName</key>' \
		'  <string>Playwright Dashboard</string>' \
		'  <key>CFBundleIconFile</key>' \
		'  <string>AppIcon</string>' \
		'  <key>CFBundlePackageType</key>' \
		'  <string>APPL</string>' \
		'  <key>CFBundleShortVersionString</key>' \
		'  <string>$(APP_VERSION)</string>' \
		'  <key>CFBundleVersion</key>' \
		'  <string>$(BUILD_NUMBER)</string>' \
		'  <key>LSApplicationCategoryType</key>' \
		'  <string>public.app-category.developer-tools</string>' \
		'  <key>NSHumanReadableCopyright</key>' \
		'  <string>Copyright © 2026 Neon Watty</string>' \
		'  <key>LSMinimumSystemVersion</key>' \
		'  <string>15.0</string>' \
		'</dict>' \
		'</plist>' > $(PACKAGE_BUNDLE)/Contents/Info.plist
	plutil -lint $(PACKAGE_BUNDLE)/Contents/Info.plist

CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 '"' | sed 's/.*"\(.*\)"/\1/' || echo -)
CODESIGN_OPTIONS ?=
DEVELOPER_ID_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed 's/.*"\(.*\)"/\1/')
NOTARY_PROFILE ?=

sign-package: $(PACKAGE_BUNDLE)
	@if [ "$(CODESIGN_IDENTITY)" = "-" ]; then \
		echo "No developer signing identity found, using ad-hoc signing"; \
		codesign --force --sign - --timestamp=none $(PACKAGE_BUNDLE); \
	elif codesign --force --sign "$(CODESIGN_IDENTITY)" $(CODESIGN_OPTIONS) $(PACKAGE_BUNDLE); then \
		echo "Signed with: $(CODESIGN_IDENTITY)"; \
	else \
		echo "ERROR: codesign failed with identity '$(CODESIGN_IDENTITY)'. Falling back to ad-hoc signing."; \
		codesign --force --sign - --timestamp=none $(PACKAGE_BUNDLE); \
	fi

package: sign-package
	rm -f $(PACKAGE_ZIP)
	cd $(DIST_DIR) && zip -qr $(APP_NAME).zip $(APP_NAME).app

validate-package: package
	test -x $(PACKAGE_BUNDLE)/Contents/MacOS/$(APP_NAME)
	test -f $(PACKAGE_BUNDLE)/Contents/Resources/AppIcon.icns
	plutil -lint $(PACKAGE_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx '$(APP_NAME)'
	/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx '$(BUNDLE_ID)'
	/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx '$(APP_VERSION)'
	/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx '$(BUILD_NUMBER)'
	/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx 'APPL'
	/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx 'AppIcon'
	codesign --verify --strict --deep $(PACKAGE_BUNDLE)
	unzip -l $(PACKAGE_ZIP) | grep -qx '.*$(APP_NAME).app/Contents/MacOS/$(APP_NAME)'
	unzip -l $(PACKAGE_ZIP) | grep -qx '.*$(APP_NAME).app/Contents/Info.plist'
	unzip -l $(PACKAGE_ZIP) | grep -qx '.*$(APP_NAME).app/Contents/Resources/AppIcon.icns'
	rm -rf $(DIST_DIR)/zipcheck
	mkdir -p $(DIST_DIR)/zipcheck
	unzip -q $(PACKAGE_ZIP) -d $(DIST_DIR)/zipcheck
	codesign --verify --strict --deep $(DIST_DIR)/zipcheck/$(APP_NAME).app
	rm -rf $(DIST_DIR)/zipcheck

beta-release: qa validate-package
	@echo "Beta artifact: $(PACKAGE_ZIP)"

developer-id-package:
	@test -n "$(DEVELOPER_ID_IDENTITY)" || { echo "No Developer ID Application identity found. Set DEVELOPER_ID_IDENTITY='Developer ID Application: ...'"; exit 2; }
	$(MAKE) package CODESIGN_IDENTITY="$(DEVELOPER_ID_IDENTITY)" CODESIGN_OPTIONS="--timestamp --options runtime"

notarize-package: developer-id-package
	@test -n "$(NOTARY_PROFILE)" || { echo "Set NOTARY_PROFILE to an xcrun notarytool keychain profile"; exit 2; }
	xcrun notarytool submit $(PACKAGE_ZIP) --keychain-profile "$(NOTARY_PROFILE)" --wait

staple-package: notarize-package
	xcrun stapler staple $(PACKAGE_BUNDLE)
	rm -f $(PACKAGE_ZIP)
	cd $(DIST_DIR) && zip -qr $(APP_NAME).zip $(APP_NAME).app

notarized-release: qa staple-package
	codesign --verify --strict --deep $(PACKAGE_BUNDLE)
	spctl --assess --type execute --verbose $(PACKAGE_BUNDLE)
	@echo "Notarized artifact: $(PACKAGE_ZIP)"

check-accessibility:
	scripts/check_accessibility.mjs

smoke-app:
	@if [ "$$RUN_GUI_SMOKE" != "1" ]; then \
		echo "Set RUN_GUI_SMOKE=1 to launch the macOS app smoke test"; \
		exit 2; \
	fi
	$(MAKE) check-accessibility
	$(MAKE) validate-package
	open $(PACKAGE_BUNDLE)
	osascript scripts/smoke_app.applescript

smoke-login-item:
	@if [ "$$RUN_LOGIN_ITEM_SMOKE" != "1" ]; then \
		echo "Set RUN_LOGIN_ITEM_SMOKE=1 to test login item registration on this machine"; \
		exit 2; \
	fi
	@echo "Login item smoke is intentionally manual; toggle Launch at login in Settings and verify System Settings > Login Items."

smoke-live-cdp:
	@if [ "$$RUN_LIVE_CDP_SMOKE" != "1" ]; then \
		echo "Set RUN_LIVE_CDP_SMOKE=1 to run against a live Playwright/CDP browser session"; \
		exit 2; \
	fi
	@PORT="$${LIVE_CDP_PORT:-$$(scripts/discover_live_cdp_port.swift)}"; \
	if [ -z "$$PORT" ]; then \
		echo "Set LIVE_CDP_PORT or start a Playwright daemon session with CDP enabled"; \
		exit 2; \
	fi; \
	cd $(PKG_DIR) && RUN_LIVE_CDP_SMOKE=1 LIVE_CDP_PORT=$$PORT \
		RUN_LIVE_CDP_INTERACTION_SMOKE=$${RUN_LIVE_CDP_INTERACTION_SMOKE:-0} \
		swift test --filter CDPClientLiveSmokeTests

smoke-expanded-interaction:
	@if [ "$$RUN_EXPANDED_INTERACTION_SMOKE" != "1" ]; then \
		echo "Set RUN_EXPANDED_INTERACTION_SMOKE=1 to drive the expanded-session interaction smoke test"; \
		exit 2; \
	fi
	$(MAKE) check-accessibility
	$(MAKE) validate-package
	scripts/smoke_expanded_interaction.mjs

smoke-expanded-fallback:
	@if [ "$$RUN_EXPANDED_FALLBACK_SMOKE" != "1" ]; then \
		echo "Set RUN_EXPANDED_FALLBACK_SMOKE=1 to drive the expanded-session fallback smoke test"; \
		exit 2; \
	fi
	$(MAKE) check-accessibility
	$(MAKE) validate-package
	SMOKE_FORCE_SNAPSHOT_FALLBACK=1 scripts/smoke_expanded_interaction.mjs

smoke-recording-export:
	@if [ "$$RUN_RECORDING_EXPORT_SMOKE" != "1" ]; then \
		echo "Set RUN_RECORDING_EXPORT_SMOKE=1 to run the recording export smoke test"; \
		exit 2; \
	fi
	$(MAKE) validate-package
	scripts/smoke_recording_export.mjs

smoke-multi-session:
	@if [ "$$RUN_MULTI_SESSION_SMOKE" != "1" ]; then \
		echo "Set RUN_MULTI_SESSION_SMOKE=1 to run the multi-session GUI smoke test"; \
		exit 2; \
	fi
	$(MAKE) check-accessibility
	$(MAKE) validate-package
	scripts/smoke_multi_session.mjs

visual-snapshots:
	$(MAKE) check-accessibility
	$(MAKE) validate-package
	scripts/snapshot_visual_states.mjs

visual-structure-smoke:
	$(MAKE) check-accessibility
	$(MAKE) validate-package
	VISUAL_SNAPSHOT_STRUCTURE_ONLY=1 \
		VISUAL_SNAPSHOT_CASES=empty-dashboard,populated-dashboard,safe-mode-dashboard,settings,closed-history \
		VISUAL_SNAPSHOT_DIR=$(DIST_DIR)/visual-structure-smoke \
		scripts/snapshot_visual_states.mjs

visual-snapshot-baseline:
	$(MAKE) check-accessibility
	$(MAKE) validate-package
	VISUAL_SNAPSHOT_DIR=$(VISUAL_SNAPSHOT_BASELINE_DIR) scripts/snapshot_visual_states.mjs

visual-snapshot-compare:
	test -d $(VISUAL_SNAPSHOT_BASELINE_DIR)
	$(MAKE) check-accessibility
	$(MAKE) validate-package
	VISUAL_SNAPSHOT_BASELINE_DIR=$(VISUAL_SNAPSHOT_BASELINE_DIR) \
		VISUAL_SNAPSHOT_DIR=$(VISUAL_SNAPSHOT_COMPARE_DIR) \
		scripts/snapshot_visual_states.mjs

visual-snapshot-enforce:
	test -d $(VISUAL_SNAPSHOT_BASELINE_DIR)
	$(MAKE) check-accessibility
	$(MAKE) validate-package
	VISUAL_SNAPSHOT_ENFORCE_DIFFS=1 \
		VISUAL_SNAPSHOT_DIFF_THRESHOLD=$(VISUAL_SNAPSHOT_DIFF_THRESHOLD) \
		VISUAL_SNAPSHOT_PIXEL_THRESHOLD=$(VISUAL_SNAPSHOT_PIXEL_THRESHOLD) \
		VISUAL_SNAPSHOT_BASELINE_DIR=$(VISUAL_SNAPSHOT_BASELINE_DIR) \
		VISUAL_SNAPSHOT_DIR=$(VISUAL_SNAPSHOT_COMPARE_DIR) \
		scripts/snapshot_visual_states.mjs

install: package
	mkdir -p $(INSTALL_DIR)
	rm -rf $(APP_BUNDLE)
	cp -R $(PACKAGE_BUNDLE) $(APP_BUNDLE)
	open $(APP_BUNDLE)

qa: lint file-size mockups test

clean:
	cd $(PKG_DIR) && swift package clean
	rm -rf $(DIST_DIR)
