CHECKS_DIR := build/checks
export DEVICE_ID SIMULATOR_ID
SUMMARY_SOURCES := rssreader/UI/Detail/ArticleSummaryText.swift \
	rssreader/UI/Detail/ArticleSummaryController.swift \
	rssreader/UI/Web/WebView.swift \
	rssreader/Core/EmbeddedWebNavigationPolicy.swift \
	tests/ArticleSummaryChecks.swift

.PHONY: help dev install install-mac install-iphone install-simulator slim-simulator simulators devices build-mac build-ios check test test-unit test-ios test-feed test-summary test-dev

help:
	@printf '%s\n' \
		'make install        Install macOS, then iPhone; attempt both even on failure' \
		'make dev            Watch edits, rebuild, and relaunch in the configured simulator' \
		'make install-mac    Archive and install the Release macOS app' \
		'make install-iphone Build, install, and launch on the configured iPhone' \
		'make install-simulator SIMULATOR_ID=<UDID>  Build, install, and launch in Simulator' \
		'make slim-simulator SIMULATOR_ID=<UDID>     Install with opt-in simslim slimming' \
		'make simulators     List available simulators and their identifiers' \
		'make devices        List available devices and their identifiers' \
		'make build-mac      Build Debug for macOS without signing or installing' \
		'make build-ios      Build Debug for iOS Simulator without installing' \
		'make check          Check shell syntax and patch whitespace' \
		'make test           Run the unit tests and all standalone macOS checks' \
		'make test-unit      Run the unit-test target on macOS' \
		'make test-ios       Run the unit-test target in the configured simulator' \
		'make test-feed      Run native feed-scrolling checks' \
		'make test-summary   Run article-summary checks without real-model generation' \
		'make test-dev       Run simulator watcher checks'

install:
	@status=0; \
		$(MAKE) install-mac || status=1; \
		$(MAKE) install-iphone || status=1; \
		exit $$status

install-mac:
	./scripts/install_mac.sh

install-iphone:
	./scripts/install_iphone.sh

install-simulator:
	bash ./scripts/install_simulator.sh

dev:
	python3 ./scripts/dev_simulator.py

slim-simulator:
	SLIM_SIMULATOR=1 bash ./scripts/install_simulator.sh

simulators:
	xcrun simctl list devices available

devices:
	xcrun devicectl list devices

build-mac:
	xcodebuild -project rssreader.xcodeproj -scheme rssreader -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath build/macos \
		CODE_SIGNING_ALLOWED=NO build

build-ios:
	xcodebuild -project rssreader.xcodeproj -scheme rssreader -configuration Debug \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios-simulator \
		CODE_SIGNING_ALLOWED=NO build

check:
	bash -n scripts/install_mac.sh
	bash -n scripts/install_iphone.sh
	bash -n scripts/install_simulator.sh
	bash -n scripts/load_env.sh
	git diff --check

test: test-unit test-feed test-summary test-dev

test-unit:
	xcodebuild test -project rssreader.xcodeproj -scheme rssreader -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath build/macos CODE_SIGNING_ALLOWED=NO

test-ios:
	@set -e; [ -f .env ] && . ./.env; \
		test -n "$$SIMULATOR_ID" || { echo 'Set SIMULATOR_ID in .env (see make simulators)'; exit 1; }; \
		xcodebuild test -project rssreader.xcodeproj -scheme rssreader -configuration Debug \
			-destination "platform=iOS Simulator,id=$$SIMULATOR_ID" -derivedDataPath build/ios-simulator CODE_SIGNING_ALLOWED=NO

test-feed: $(CHECKS_DIR)/feed-scroll-checks
	./$(CHECKS_DIR)/feed-scroll-checks

test-summary: $(CHECKS_DIR)/article-summary-checks
	./$(CHECKS_DIR)/article-summary-checks

$(CHECKS_DIR):
	mkdir -p "$@"

$(CHECKS_DIR)/feed-scroll-checks: rssreader/UI/Feed/FeedSkipTracking.swift tests/FeedScrollChecks.swift | $(CHECKS_DIR)
	swiftc -parse-as-library $^ -o "$@"

$(CHECKS_DIR)/article-summary-checks: $(SUMMARY_SOURCES) | $(CHECKS_DIR)
	swiftc -parse-as-library $^ -o "$@"
