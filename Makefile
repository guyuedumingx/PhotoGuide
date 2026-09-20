.PHONY: core-test recipe-test localization-test test generate

core-test:
	swift test --package-path Packages/GuidanceCore

recipe-test:
	swift test --package-path Packages/RecipeKit

localization-test:
	./scripts/validate-localization.py

test: core-test recipe-test localization-test

generate:
	xcodegen generate
