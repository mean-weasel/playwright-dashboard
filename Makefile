.PHONY: build test lint file-size mockups package sign-package validate-package smoke-app smoke-login-item smoke-live-cdp install clean qa

APP_NAME := PlaywrightDashboard
PKG_DIR := PlaywrightDashboard
BUILD_DIR := $(PKG_DIR)/.build
INSTALL_DIR := $(HOME)/Applications
APP_BUNDLE := $(INSTALL_DIR)/$(APP_NAME).app
DIST_DIR := dist
PACKAGE_BUNDLE := $(DIST_DIR)/$(APP_NAME).app

build:
	cd $(PKG_DIR) && swift build

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
	mkdir -p $(PACKAGE_BUNDLE)/Contents/MacOS
	cp $(BUILD_DIR)/debug/$(APP_NAME) $(PACKAGE_BUNDLE)/Contents/MacOS/$(APP_NAME)
	chmod +x $(PACKAGE_BUNDLE)/Contents/MacOS/$(APP_NAME)
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
		'  <key>CFBundlePackageType</key>' \
		'  <string>APPL</string>' \
		'  <key>CFBundleVersion</key>' \
		'  <string>1</string>' \
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
	plutil -lint $(PACKAGE_BUNDLE)/Contents/Info.plist
	/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx '$(APP_NAME)'
	/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' $(PACKAGE_BUNDLE)/Contents/Info.plist | grep -qx 'APPL'
	codesign --verify --strict --deep $(PACKAGE_BUNDLE)
	unzip -l $(DIST_DIR)/$(APP_NAME).zip | grep -qx '.*$(APP_NAME).app/Contents/MacOS/$(APP_NAME)'
	unzip -l $(DIST_DIR)/$(APP_NAME).zip | grep -qx '.*$(APP_NAME).app/Contents/Info.plist'
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
	@sleep 2
	@pgrep -x $(APP_NAME) >/dev/null
	@osascript -e 'tell application "$(APP_NAME)" to quit' >/dev/null 2>&1 || true

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
	@if [ -z "$$LIVE_CDP_PORT" ]; then \
		echo "Set LIVE_CDP_PORT to the browser's remote debugging port"; \
		exit 2; \
	fi
	cd $(PKG_DIR) && RUN_LIVE_CDP_SMOKE=1 LIVE_CDP_PORT=$$LIVE_CDP_PORT swift test --filter CDPClientLiveSmokeTests

install: package
	mkdir -p $(INSTALL_DIR)
	rm -rf $(APP_BUNDLE)
	cp -R $(PACKAGE_BUNDLE) $(APP_BUNDLE)
	open $(APP_BUNDLE)

qa: lint file-size mockups test

clean:
	cd $(PKG_DIR) && swift package clean
	rm -rf $(DIST_DIR)
