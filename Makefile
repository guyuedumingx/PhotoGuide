.PHONY: core-test recipe-test localization-test ablation-test benchmark-self-test test generate release-audit market-audit

core-test:
	swift test --package-path Packages/GuidanceCore

recipe-test:
	swift test --package-path Packages/RecipeKit

localization-test:
	./scripts/validate-localization.py

ablation-test:
	./scripts/run-ablation.py

benchmark-self-test:
	./scripts/evaluate-critic-benchmark.py --self-test

test: core-test recipe-test localization-test ablation-test benchmark-self-test

generate:
	./scripts/prepare-xcode.sh

release-audit:
	./scripts/release-audit.py

market-audit:
	./scripts/release-audit.py --market-release
