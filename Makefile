APP_NAME := TouchBarUsageMonitor
BUILD_DIR := build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
BINARY := $(MACOS_DIR)/$(APP_NAME)
TEST_BINARY := $(BUILD_DIR)/parser-tests
CONTROLLER_TEST_BINARY := $(BUILD_DIR)/controller-tests
SMOKE_BINARY := $(BUILD_DIR)/provider-smoke

CLANG := $(shell xcrun --find clang)
SDK := $(shell xcrun --show-sdk-path)
MODULE_CACHE := $(CURDIR)/.build/module-cache
COMMON_FLAGS := -isysroot $(SDK) -mmacosx-version-min=12.0 -fobjc-arc -fmodules \
	-fmodules-cache-path=$(MODULE_CACHE) -Wall -Wextra -Wpedantic -Wno-nullability-completeness \
	-I$(CURDIR)/Sources
APP_FLAGS := $(COMMON_FLAGS) -framework AppKit -framework Foundation -framework Security
TEST_FLAGS := $(COMMON_FLAGS) -framework Foundation
SOURCES := $(wildcard Sources/*.m)

.PHONY: all build test smoke install uninstall clean

all: test build

build: $(BINARY)

$(BINARY): $(SOURCES) Resources/Info.plist
	mkdir -p $(MACOS_DIR) $(MODULE_CACHE)
	$(CLANG) $(APP_FLAGS) $(SOURCES) -o $(BINARY)
	cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	codesign --force --sign - --timestamp=none $(APP_DIR)

$(TEST_BINARY): Sources/TUMModels.m Sources/TUMParsers.m Tests/parser_tests.m
	mkdir -p $(BUILD_DIR) $(MODULE_CACHE)
	$(CLANG) $(TEST_FLAGS) $^ -o $@

test: $(TEST_BINARY)
	$(TEST_BINARY)
	$(MAKE) $(CONTROLLER_TEST_BINARY)
	$(CONTROLLER_TEST_BINARY)

$(CONTROLLER_TEST_BINARY): Sources/TUMModels.m Sources/TUMUsageCardView.m Sources/TUMTouchBarController.m Tests/controller_tests.m
	mkdir -p $(BUILD_DIR) $(MODULE_CACHE)
	$(CLANG) $(COMMON_FLAGS) -framework AppKit -framework Foundation $^ -o $@

$(SMOKE_BINARY): Sources/TUMModels.m Sources/TUMParsers.m Sources/TUMProviders.m Tests/provider_smoke.m
	mkdir -p $(BUILD_DIR) $(MODULE_CACHE)
	$(CLANG) $(COMMON_FLAGS) -framework Foundation -framework Security $^ -o $@

smoke: $(SMOKE_BINARY)
	$(SMOKE_BINARY)

install: build
	Scripts/install.sh

uninstall:
	Scripts/uninstall.sh

clean:
	rm -rf $(BUILD_DIR) .build .build-*
