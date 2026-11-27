CHECKS_DIR := build/checks
SUMMARY_SOURCES := rssreader/UI/Detail/ArticleSummaryText.swift \
	rssreader/UI/Detail/ArticleSummaryController.swift \
	rssreader/UI/Web/WebView.swift \
	rssreader/Core/EmbeddedWebNavigationPolicy.swift \
	tests/ArticleSummaryChecks.swift

.PHONY: help install install-mac install-iphone devices build-mac build-ios check test test-feed test-skipped test-summary test-karakeep

help:
	@printf '%s\n' \
		'make install        Install macOS, then iPhone; attempt both even on failure' \
		'make install-mac    Archive and install the Release macOS app' \
		'make install-iphone Build, install, and launch on the configured iPhone' \
		'make devices        List available devices and their identifiers' \
		'make build-mac      Build Debug for macOS without signing or installing' \
		'make build-ios      Build Debug for iOS Simulator without installing' \
		'make check          Check shell syntax and patch whitespace' \
		'make test           Run all standalone macOS checks' \
		'make test-feed      Run native feed-scrolling checks' \
		'make test-skipped   Run skipped-item persistence checks' \
		'make test-summary   Run article-summary checks without real-model generation' \
		'make test-karakeep  Run Karakeep request and response checks'

install:
	@status=0; \
		$(MAKE) install-mac || status=1; \
		$(MAKE) install-iphone || status=1; \
		exit $$status

install-mac:
	./scripts/install_mac.sh

install-iphone:
	./scripts/install_iphone.sh

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
	git diff --check

test: test-feed test-skipped test-summary test-karakeep

test-feed: $(CHECKS_DIR)/feed-scroll-checks
	./$(CHECKS_DIR)/feed-scroll-checks

test-skipped: $(CHECKS_DIR)/skipped-items-checks
	./$(CHECKS_DIR)/skipped-items-checks

test-summary: $(CHECKS_DIR)/article-summary-checks
	./$(CHECKS_DIR)/article-summary-checks

test-karakeep: $(CHECKS_DIR)/karakeep-checks
	./$(CHECKS_DIR)/karakeep-checks

$(CHECKS_DIR):
	mkdir -p "$@"

$(CHECKS_DIR)/feed-scroll-checks: rssreader/UI/Feed/FeedSkipTracking.swift tests/FeedScrollChecks.swift | $(CHECKS_DIR)
	swiftc -parse-as-library $^ -o "$@"

$(CHECKS_DIR)/skipped-items-checks: rssreader/Core/Models/SkippedItems.swift tests/SkippedItemsChecks.swift | $(CHECKS_DIR)
	swiftc -parse-as-library $^ -o "$@"

$(CHECKS_DIR)/article-summary-checks: $(SUMMARY_SOURCES) | $(CHECKS_DIR)
	swiftc -parse-as-library $^ -o "$@"

$(CHECKS_DIR)/karakeep-checks: rssreader/Core/Services/KarakeepClient.swift tests/KarakeepChecks.swift | $(CHECKS_DIR)
	swiftc -parse-as-library $^ -o "$@"
