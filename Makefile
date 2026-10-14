# PatchAdam — factory targets. See FACTORY.md for the runbook.

XCODEGEN   := xcodegen
SWIFT      := swift
XCODEBUILD := xcodebuild

PROJECT := PatchAdam.xcodeproj
SCHEME  := PatchAdam
DEST    := platform=macOS

.PHONY: all generate build test harness bases audit clean

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

clean:
	rm -rf .build $(PROJECT)
