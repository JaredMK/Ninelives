# Shoulda Said Same — iOS. Every command is reproducible from a clean checkout.
#
#   make            # regenerate the project, build, test
#   make test       # run the XCTest suite
#   make data       # re-export items.js / difficulty.js / tutorial.js → JSON
#   make golden     # re-record the golden baseline from GameCore itself
#   make verify-launch   # boot the app in the simulator and read its boot receipt
#   make perf       # play a scripted 12-pile deal and print its frame timings
#   make device-run # build, install and launch on a connected iPhone

SIM      ?= iPhone 17
PROJECT   = ShouldaSaidSame.xcodeproj
DD        = build/DerivedData
BUNDLE_ID = com.ninelives.shouldasaidsame

.PHONY: all project build test data golden app verify-launch device device-run perf clean

all: project build test

project:
	xcodegen generate --spec project.yml

# BOTH schemes. The GameCore scheme compiles the engine and its tests only —
# it does NOT compile UI/, so an app-target break (a call site left behind by
# an engine signature change) can sit unnoticed through a green `make test`.
# That happened once; `build` covers both now.
build: project
	xcodebuild build -project $(PROJECT) -scheme GameCore \
	  -destination 'platform=iOS Simulator,name=$(SIM)'
	xcodebuild build -project $(PROJECT) -scheme ShouldaSaidSame \
	  -destination 'platform=iOS Simulator,name=$(SIM)'

# The engine suite, and then the APP target's compile — green here means the
# whole port builds, not just GameCore.
test: project
	xcodebuild test -project $(PROJECT) -scheme GameCore \
	  -destination 'platform=iOS Simulator,name=$(SIM)'
	xcodebuild build -project $(PROJECT) -scheme ShouldaSaidSame \
	  -destination 'platform=iOS Simulator,name=$(SIM)'

# The three JS data files stay the hand-editable source of truth. Re-run this
# after ANY edit to them, then rebuild.
data:
	node Tools/export-data.mjs

# THE GOLDEN BASELINE (v6.79): `Fixtures/*.json` is recorded from GameCore
# ITSELF — the iOS engine is the source of truth; the web engine is frozen
# and never consulted. Re-record ONLY after an INTENTIONAL engine change, in
# the same commit, then `make test` must be green against the new baseline.
# The flag file arms `GoldenRecorder` (a normal test run always skips it).
golden: project
	touch Fixtures/.golden-record
	xcodebuild test -project $(PROJECT) -scheme GameCore \
	  -destination 'platform=iOS Simulator,name=$(SIM)' \
	  -only-testing:GameCoreTests/GoldenRecorder \
	  || (rm -f Fixtures/.golden-record; exit 1)
	rm -f Fixtures/.golden-record
	@echo "golden baseline re-recorded — review the Fixtures/ diff, then run: make test"

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
	xcrun simctl launch $$SIMID $(BUNDLE_ID) -bootSmoke 1; \
	sleep 4; \
	xcrun simctl spawn $$SIMID launchctl list | grep -q $(BUNDLE_ID) \
	  && echo "✅ still running after 4s — no crash" || (echo "❌ process gone — it crashed"; exit 1); \
	echo "--- boot receipt ---"; \
	cat "$$(xcrun simctl get_app_container $$SIMID $(BUNDLE_ID) data)/Documents/boot-receipt.json"

# ── Device ────────────────────────────────────────────────────────────────
# Needs your Team ID once:  echo 'DEVELOPMENT_TEAM = ABCDE12345' > Local.xcconfig
device: project
	xcodebuild build -project $(PROJECT) -scheme ShouldaSaidSame \
	  -destination 'generic/platform=iOS' -derivedDataPath $(DD) -allowProvisioningUpdates

# Install + launch on the first connected iPhone.
device-run: device
	@UDID=$$(xcrun devicectl list devices --hide-headers 2>/dev/null | grep -i 'available' | grep -iv watch | head -1 | awk '{print $$3}'); \
	if [ -z "$$UDID" ]; then echo "No connected iPhone found — plug it in, unlock it, and trust this Mac."; exit 1; fi; \
	echo "installing to $$UDID"; \
	xcrun devicectl device install app --device $$UDID $(DD)/Build/Products/Debug-iphoneos/ShouldaSaidSame.app; \
	xcrun devicectl device process launch --device $$UDID $(BUNDLE_ID)

# A scripted deal + its frame timings, on the simulator.
perf: app
	@SIMID=$$(xcrun simctl list devices available -j | python3 -c \
	  "import json,sys;d=json.load(sys.stdin)['devices'];print(next(x['udid'] for r in d for x in d[r] if x['name']=='$(SIM)'))"); \
	xcrun simctl boot $$SIMID 2>/dev/null || true; \
	xcrun simctl bootstatus $$SIMID -b >/dev/null 2>&1 || true; \
	xcrun simctl install $$SIMID $(DD)/Build/Products/Debug-iphonesimulator/ShouldaSaidSame.app; \
	rm -f "$$(xcrun simctl get_app_container $$SIMID $(BUNDLE_ID) data)/Documents/deal-receipt.json"; \
	xcrun simctl launch $$SIMID $(BUNDLE_ID) -autoDeal 1 -autoPlay 1 -piles 12 -cards 52 -seed 909 -items 1 -fps 1; \
	echo "playing a scripted 12-pile deal…"; sleep 30; \
	cat "$$(xcrun simctl get_app_container $$SIMID $(BUNDLE_ID) data)/Documents/deal-receipt.json"

clean:
	rm -rf $(DD) $(PROJECT)
