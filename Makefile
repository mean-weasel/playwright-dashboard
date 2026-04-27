.PHONY: build test lint file-size install clean qa

APP_NAME := PlaywrightDashboard
PKG_DIR := PlaywrightDashboard
BUILD_DIR := $(PKG_DIR)/.build
INSTALL_DIR := $(HOME)/Applications

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

install: build
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	cp -R $(BUILD_DIR)/debug/$(APP_NAME) $(INSTALL_DIR)/$(APP_NAME).app
	open $(INSTALL_DIR)/$(APP_NAME).app

qa: lint file-size test

clean:
	cd $(PKG_DIR) && swift package clean
