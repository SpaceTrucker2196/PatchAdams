# Patch Adams — factory targets. See FACTORY.md for the runbook.

XCODEGEN   := xcodegen
SWIFT      := swift
XCODEBUILD := xcodebuild

PROJECT := PatchAdams.xcodeproj
SCHEME  := PatchAdams
DEST    := platform=macOS

.PHONY: all generate build test harness bases audit clean release dmg notarize

all: test build

# The oracle. Engine packages, coverage on — cygnus reads the
# resulting codecov artifact under .build/<triple>/debug/codecov/.
test:
	$(SWIFT) test --enable-code-coverage

# Regenerate the Xcode project from project.yml (the .xcodeproj is
# gitignored; project.yml is the source of truth).
generate:
	$(XCODEGEN) generate

# Build the macOS app. Warnings are errors in project.yml, so a
# warning fails this target.
build: generate
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
	  -derivedDataPath .build/DerivedData build

# Smoke-run the engines on every fixture patch: parse all, then apply
# each against its synthetic base (every file must come back clean).
harness:
	$(SWIFT) run patchadam parse Fixtures/patches/*.patch
	for p in Fixtures/patches/*.patch; do \
	  $(SWIFT) run patchadam apply Fixtures/bases/$$(basename $$p .patch) $$p || exit 1; \
	done

# Regenerate Fixtures/bases from the fixture patches (issue #6, D4).
# SyntheticBaseTests fails when the stored set drifts from this output.
bases:
	rm -rf Fixtures/bases
	for p in Fixtures/patches/*.patch; do \
	  $(SWIFT) run patchadam synth-base $$p Fixtures/bases/$$(basename $$p .patch) || exit 1; \
	done

# Workflow audit: zero dependencies, grep and awk only.
audit:
	@tools/audit-workflows.sh

# --- Distribution (D2, M5): a notarized DMG ---------------------------
# SIGN is the signing identity. The default "-" is ad-hoc: the DMG
# builds and runs locally but cannot be notarized. For a release set
# SIGN='Developer ID Application: river.io llc (U3Z59VXPUB)' — that
# certificate is made once by the account holder (owner task).
SIGN    ?= -
VERSION := $(shell sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
RELEASE := .build/Release
APP     := $(RELEASE)/PatchAdams.app
DMG     := .build/PatchAdams-$(VERSION).dmg
# Notarization credentials: the App Store Connect API key on this box
# (see ~/projects/skill-fastlane-appstore/reference/credentials.md).
NOTARY_KEY_ID ?= 6SXNN2PVAB
NOTARY_KEY    ?= $(HOME)/.appstoreconnect/private_keys/AuthKey_$(NOTARY_KEY_ID).p8
NOTARY_ISSUER ?= 69a6de84-cb86-47e3-e053-5b8c7c11a4d1

# Release build, signed with $(SIGN) under the hardened runtime.
release: generate
	rm -rf $(RELEASE)
	$(XCODEBUILD) -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	  -destination '$(DEST)' -derivedDataPath .build/DerivedData \
	  CODE_SIGN_IDENTITY='$(SIGN)' CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=U3Z59VXPUB \
	  OTHER_CODE_SIGN_FLAGS=--timestamp build
	mkdir -p $(RELEASE)
	cp -R .build/DerivedData/Build/Products/Release/PatchAdams.app $(APP)
	codesign --verify --deep --strict $(APP)
	@echo "release: $(APP) signed as '$(SIGN)'"

# The DMG: the app plus an Applications symlink, compressed.
dmg: release
	rm -rf $(RELEASE)/dmg $(DMG)
	mkdir -p $(RELEASE)/dmg
	cp -R $(APP) $(RELEASE)/dmg/
	ln -s /Applications $(RELEASE)/dmg/Applications
	hdiutil create -volname "Patch Adams $(VERSION)" -srcfolder $(RELEASE)/dmg -ov -format UDZO $(DMG)
	@if [ '$(SIGN)' != '-' ]; then codesign --sign '$(SIGN)' --timestamp $(DMG); fi
	@echo "dmg: $(DMG)"

# Submit the DMG to Apple, wait, staple. Needs SIGN set to a Developer
# ID identity (ad-hoc signatures are rejected) and the API key on disk.
notarize:
	@test '$(SIGN)' != '-' || { echo "notarize: set SIGN to a Developer ID Application identity"; exit 1; }
	@test -f $(NOTARY_KEY) || { echo "notarize: no API key at $(NOTARY_KEY)"; exit 1; }
	xcrun notarytool submit $(DMG) --key $(NOTARY_KEY) --key-id $(NOTARY_KEY_ID) --issuer $(NOTARY_ISSUER) --wait
	xcrun stapler staple $(DMG)
	spctl --assess --type open --context context:primary-signature -v $(DMG)
	@echo "notarize: $(DMG) stapled"

clean:
	rm -rf .build $(PROJECT)
