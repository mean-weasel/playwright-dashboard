.PHONY: build test lint file-size mockups package sign-package validate-package smoke-app smoke-login-item smoke-live-cdp install clean qa

APP_NAME := PlaywrightDashboard
PKG_DIR := PlaywrightDashboard
BUILD_DIR := $(PKG_DIR)/.build
CONFIGURATION ?= release
BUILD_CONFIG_FLAG := -c $(CONFIGURATION)
SWIFT_BUILD_DIR := $(BUILD_DIR)/$(CONFIGURATION)
INSTALL_DIR := $(HOME)/Applications
APP_BUNDLE := $(INSTALL_DIR)/$(APP_NAME).app
DIST_DIR := dist
PACKAGE_BUNDLE := $(DIST_DIR)/$(APP_NAME).app

build:
	cd $(PKG_DIR) && swift build $(BUILD_CONFIG_FLAG)

test:
	cd $(PKG_DIR) && swift test

lint:
	swift-format lint --recursive $(PKG_DIR)/Sources $(PKG_DIR)/Tests

format:
	swift-format format --recursive --in-place $(PKG_DIR)/Sources $(PKG_DIR)/Tests

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
		'  <string>com.neonwatty.PlaywrightDashboard</string>' \
		'  <key>CFBundleName</key>' \
		'  <string>$(APP_NAME)</string>' \
		'  <key>CFBundleDisplayName</key>' \
		'  <string>Playwright Dashboard</string>' \
		'  <key>CFBundleIconFile</key>' \
		'  <string>AppIcon</string>' \
		'  <key>CFBundlePackageType</key>' \
		'  <string>APPL</string>' \
		'  <key>CFBundleShortVersionString</key>' \
		'  <string>0.1.0</string>' \
		'  <key>CFBundleVersion</key>' \
		'  <string>1</string>' \
		'  <key>LSApplicationCategoryType</key>' \
		'  <string>public.app-category.developer-tools</string>' \
		'  <key>NSHumanReadableCopyright</key>' \
		'  <string>Copyright © 2026 Neon Watty</string>' \
		'  <key>LSMinimumSystemVersion</key>' \
		'  <string>15.0</string>' \
		'</dict>' \
		'</plist>' > $(PACKAGE_BUNDLE)/Contents/Info.plist
	plutil -lint $(PACKAGE_BUNDLE)/Contents/Info.plist

sign-package: $(PACKAGE_BUNDLE)
	codesign --force --sign - --timestamp=none $(PACKAGE_BUNDLE)

package: sign-package
	rm -f $(DIST_DIR)/$(APP_NAME).zip
	cd $(DIST_DIR) && zip -qr $(APP_NAME).zip $(APP_NAME).app

validate-package: package
	test -x $(PACKAGE_BUNDLE)/Contents/MacOS/$(APP_NAME)
	test -f $(PACKAGE_BUNDLE)/Contents/Resources/AppIcon.icns
	plutil -lint $(PACKAGE_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx '$(APP_NAME)'
	/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx 'APPL'
	/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx 'AppIcon'
	codesign --verify --strict --deep $(PACKAGE_BUNDLE)
	unzip -l $(DIST_DIR)/$(APP_NAME).zip | grep -qx '.*$(APP_NAME).app/Contents/MacOS/$(APP_NAME)'
	unzip -l $(DIST_DIR)/$(APP_NAME).zip | grep -qx '.*$(APP_NAME).app/Contents/Info.plist'
	unzip -l $(DIST_DIR)/$(APP_NAME).zip | grep -qx '.*$(APP_NAME).app/Contents/Resources/AppIcon.icns'
	rm -rf $(DIST_DIR)/zipcheck
	mkdir -p $(DIST_DIR)/zipcheck
	unzip -q $(DIST_DIR)/$(APP_NAME).zip -d $(DIST_DIR)/zipcheck
	codesign --verify --strict --deep $(DIST_DIR)/zipcheck/$(APP_NAME).app
	rm -rf $(DIST_DIR)/zipcheck

smoke-app: validate-package
	@if [ "$$RUN_GUI_SMOKE" != "1" ]; then \
		echo "Set RUN_GUI_SMOKE=1 to launch the macOS app smoke test"; \
		exit 2; \
	fi
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

install: package
	mkdir -p $(INSTALL_DIR)
	rm -rf $(APP_BUNDLE)
	cp -R $(PACKAGE_BUNDLE) $(APP_BUNDLE)
	open $(APP_BUNDLE)

qa: lint file-size mockups test

clean:
	cd $(PKG_DIR) && swift package clean
	rm -rf $(DIST_DIR)
