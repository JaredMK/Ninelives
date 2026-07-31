# Shoulda Said Same — iOS. Every command is reproducible from a clean checkout.
#
#   make            # regenerate the project, build, test
#   make test       # run the XCTest suite
#   make data       # re-export items.js / difficulty.js / tutorial.js → JSON
#   make fixtures   # re-capture the web-engine ground truth (needs the web repo)
#   make verify-launch   # boot the app in the simulator and read its boot receipt

SIM      ?= iPhone 17
PROJECT   = ShouldaSaidSame.xcodeproj
DD        = build/DerivedData
BUNDLE_ID = com.ninelives.shouldasaidsame

.PHONY: all project build test data fixtures app verify-launch clean

all: project build test

project:
	xcodegen generate --spec project.yml

build: project
	xcodebuild build -project $(PROJECT) -scheme GameCore \
	  -destination 'platform=iOS Simulator,name=$(SIM)'

test: project
	xcodebuild test -project $(PROJECT) -scheme GameCore \
	  -destination 'platform=iOS Simulator,name=$(SIM)'

# The three JS data files stay the hand-editable source of truth. Re-run this
# after ANY edit to them, then rebuild.
data:
	node Tools/export-data.mjs

# Ground truth captured by running the REAL web engine. Re-run when the web
# engine changes, then re-run `make test` to see whether iOS still agrees.
fixtures:
	node Tools/export-fixtures.mjs
	node Tools/export-traces.mjs
	node Tools/export-campaign.mjs

app: project
	xcodebuild build -project $(PROJECT) -scheme ShouldaSaidSame \
	  -destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath $(DD)

verify-launch: app
	@SIMID=$$(xcrun simctl list devices available -j | python3 -c \
	  "import json,sys;d=json.load(sys.stdin)['devices'];print(next(x['udid'] for r in d for x in d[r] if x['name']=='$(SIM)'))"); \
	xcrun simctl boot $$SIMID 2>/dev/null || true; \
	xcrun simctl bootstatus $$SIMID -b >/dev/null 2>&1 || true; \
	xcrun simctl terminate $$SIMID $(BUNDLE_ID) 2>/dev/null || true; \
	xcrun simctl uninstall $$SIMID $(BUNDLE_ID) 2>/dev/null || true; \
	xcrun simctl install $$SIMID $(DD)/Build/Products/Debug-iphonesimulator/ShouldaSaidSame.app; \
	xcrun simctl launch $$SIMID $(BUNDLE_ID); \
	sleep 4; \
	xcrun simctl spawn $$SIMID launchctl list | grep -q $(BUNDLE_ID) \
	  && echo "✅ still running after 4s — no crash" || (echo "❌ process gone — it crashed"; exit 1); \
	echo "--- boot receipt ---"; \
	cat "$$(xcrun simctl get_app_container $$SIMID $(BUNDLE_ID) data)/Documents/boot-receipt.json"

clean:
	rm -rf $(DD) $(PROJECT)
