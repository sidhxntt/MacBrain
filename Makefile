APP_NAME := MacBrain
BUNDLE_ID := com.macbrain.app
BUILD_SCRIPT := script/build_and_run.sh
TEST_ENV := CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-cache SWIFTPM_CACHE_PATH=/tmp/macbrain-swiftpm-cache
PERMISSION_RESET ?= 0

.DEFAULT_GOAL := help
.PHONY: help start stop stop-permissions-reset permission-reset restart build release release-check test verify status logs telemetry

help:
	@echo "MacBrain commands:"
	@echo "  make start      Build and launch MacBrain"
	@echo "  make stop       Close MacBrain"
	@echo "  make stop PERMISSION_RESET=1  Close MacBrain and reset its macOS consent decisions"
	@echo "  make stop-permissions-reset    Alias for the permission-reset stop command"
	@echo "  make restart    Close, rebuild, and relaunch MacBrain"
	@echo "  make build      Build the .app bundle without launching"
	@echo "  make release SIGNING_IDENTITY='Developer ID Application: …'  Build and sign a beta bundle"
	@echo "  make release-check  Validate a signed bundle and privacy declarations"
	@echo "  make test       Run the Swift test suite"
	@echo "  make verify     Build, launch, and verify the process"
	@echo "  make status     Show whether MacBrain is running"
	@echo "  make logs       Launch and stream process logs"
	@echo "  make telemetry  Launch and stream MacBrain telemetry"

start:
	bash $(BUILD_SCRIPT)

stop:
	@if pgrep -x "$(APP_NAME)" >/dev/null; then \
		pkill -TERM -x "$(APP_NAME)"; \
		echo "MacBrain closed"; \
	else \
		echo "MacBrain is not running"; \
	fi
	@if [ "$(PERMISSION_RESET)" = "1" ]; then \
		$(MAKE) --no-print-directory permission-reset; \
	fi

stop-permissions-reset:
	@$(MAKE) --no-print-directory stop PERMISSION_RESET=1

permission-reset:
	@/usr/bin/tccutil reset All "$(BUNDLE_ID)"
	@echo "MacBrain permissions reset. The next make start will request supported app permissions again."

restart: stop start

build:
	bash $(BUILD_SCRIPT) --bundle

release:
	bash $(BUILD_SCRIPT) --release

release-check:
	bash script/release_check.sh dist/$(APP_NAME).app

test:
	env $(TEST_ENV) swift test --disable-sandbox

verify:
	bash $(BUILD_SCRIPT) --verify

status:
	@if pgrep -x "$(APP_NAME)" >/dev/null; then \
		echo "MacBrain is running"; \
	else \
		echo "MacBrain is not running"; \
	fi

logs:
	bash $(BUILD_SCRIPT) --logs

telemetry:
	bash $(BUILD_SCRIPT) --telemetry
