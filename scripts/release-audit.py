#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description="Audit PhotoGuide v0.9 question-core release contracts")
parser.add_argument(
    "--market-release",
    action="store_true",
    help="Also require a real held-out DJev frame-vs-reference benchmark artifact",
)
args = parser.parse_args()

errors: list[str] = []
notes: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def run(command: list[str], label: str) -> None:
    proc = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if proc.returncode:
        errors.append(f"{label} failed:\n{proc.stdout}{proc.stderr}")
        return
    output = (proc.stdout + proc.stderr).strip()
    if output:
        notes.append(f"{label}: {output.splitlines()[-1]}")


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8", errors="ignore")


# ---- General shipping hygiene ---------------------------------------------
run([sys.executable, "scripts/validate-localization.py"], "localization")

privacy = ROOT / "PhotoGuideApp/Resources/PrivacyInfo.xcprivacy"
require(privacy.exists(), "PrivacyInfo.xcprivacy is missing")
if privacy.exists():
    try:
        data = plistlib.loads(privacy.read_bytes())
        require(data.get("NSPrivacyTracking") is False, "Privacy manifest must explicitly disable tracking")
        require(data.get("NSPrivacyTrackingDomains") == [], "Tracking domains must remain empty")
        reasons = {
            item.get("NSPrivacyAccessedAPIType"): set(item.get("NSPrivacyAccessedAPITypeReasons", []))
            for item in data.get("NSPrivacyAccessedAPITypes", [])
        }
        require(
            "CA92.1" in reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", set()),
            "UserDefaults required-reason declaration CA92.1 is missing",
        )
    except Exception as exc:
        errors.append(f"Privacy manifest is invalid: {exc}")

try:
    from PIL import Image

    icon_dir = ROOT / "PhotoGuideApp/Assets.xcassets/AppIcon.appiconset"
    for filename in ["AppIcon-1024.png", "AppIcon-1024-dark.png", "AppIcon-1024-tinted.png"]:
        path = icon_dir / filename
        require(path.exists(), f"Missing app icon: {filename}")
        if path.exists():
            image = Image.open(path)
            require(image.size == (1024, 1024), f"{filename} must be 1024×1024")
            require("A" not in image.mode, f"{filename} must not contain alpha/transparency")
except Exception as exc:
    errors.append(f"Unable to validate app icon assets: {exc}")

shipping_roots = [ROOT / "Packages", ROOT / "PhotoGuideApp"]
for base in shipping_roots:
    for path in base.rglob("*.swift"):
        if ".build" in path.parts:
            continue
        source = path.read_text(encoding="utf-8", errors="ignore")
        if re.search(r"\b(?:TODO|FIXME)\b", source):
            errors.append(f"Shipping TODO/FIXME remains in {path.relative_to(ROOT)}")
        if re.search(r"(?m)^\s*print\(", source):
            errors.append(f"Debug print remains in {path.relative_to(ROOT)}")

# Old bundled Recipes remain parseable compatibility assets. They are NOT the
# v0.9 core contract because they predate portable references + bounded questions.
recipe_dir = ROOT / "Packages/RecipeKit/Resources"
recipe_files = sorted(recipe_dir.glob("*.recipe.json"))
require(len(recipe_files) >= 10, "Expected the legacy bundled Recipe catalog to remain available")
for path in recipe_files:
    try:
        doc = json.loads(path.read_text(encoding="utf-8"))
        require(doc.get("kind") == "Recipe", f"{path.name}: invalid Recipe kind")
        require(bool(doc.get("id")), f"{path.name}: id is missing")
    except Exception as exc:
        errors.append(f"{path.name}: invalid JSON: {exc}")

# ---- Version / transport ---------------------------------------------------
project_yml = text("project.yml")
for token in [
    "PRODUCT_BUNDLE_IDENTIFIER: com.guyuedumingx.PhotoGuide",
    "MARKETING_VERSION: 0.9.4",
    "CURRENT_PROJECT_VERSION: 27",
    "DJEV_ENDPOINT:",
    'INFOPLIST_KEY_DJEVEndpoint: "$(DJEV_ENDPOINT)"',
    "INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.photography",
    "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon",
    "Packages/RecipeKit/RecipeQuestion.swift",
]:
    require(token in project_yml, f"project.yml is missing release setting/source: {token}")
require("DJEV_TOKEN" not in project_yml, "DJEV_TOKEN must not be embedded in project.yml")
require("MULTIMODAL_CRITIC_TOKEN" not in project_yml, "Model tokens must not be embedded in project.yml")

# ---- v0.9 minimal System-1 core -------------------------------------------
visual_judge_path = ROOT / "Packages/GuidanceCore/Sources/GuidanceCore/Runtime/VisualJudge.swift"
recipe_question_path = ROOT / "Packages/RecipeKit/RecipeQuestion.swift"
coordinator_path = ROOT / "Packages/GuidanceUI/QuestionGuidanceCoordinator.swift"
for path in [visual_judge_path, recipe_question_path, coordinator_path]:
    require(path.exists(), f"Missing v0.9 core file: {path.relative_to(ROOT)}")

visual_judge = visual_judge_path.read_text(encoding="utf-8", errors="ignore") if visual_judge_path.exists() else ""
for token in [
    "public protocol VisualJudge",
    "case choice(String)",
    "case score(Double)",
    "case boolean(Bool)",
    "public struct QuestionRuntime",
    "public mutating func skip",
    "public mutating func restore",
    "public func issueSnapshots()",
    "if let unseen = active.first",
    "question.answerSpec.accepts(answer)",
]:
    require(token in visual_judge, f"VisualJudge question core is missing: {token}")

# No free-form coaching/action result is allowed in JudgeAnswer.
answer_body_match = re.search(r"public enum JudgeAnswer.*?\{(.*?)\n\}", visual_judge, re.S)
require(answer_body_match is not None, "Unable to inspect JudgeAnswer")
if answer_body_match:
    answer_body = answer_body_match.group(1).lower()
    for forbidden in ["action", "advice", "rationale", "instruction", "hint"]:
        require(forbidden not in answer_body, f"JudgeAnswer leaked free-form field: {forbidden}")

recipe_question = recipe_question_path.read_text(encoding="utf-8", errors="ignore") if recipe_question_path.exists() else ""
for token in [
    "RecipeReferenceDTO",
    "RecipeQuestionDTO",
        "case choice",
    "case score",
    "case boolean",
    "questionRecipe(",
]:
    require(token in recipe_question, f"Recipe question contract is missing: {token}")
question_dto_match = re.search(r"public struct RecipeQuestionDTO.*?\{(.*?)\n\}", recipe_question, re.S)
require(question_dto_match is not None, "Unable to inspect RecipeQuestionDTO")
require("public let priority: Double" not in recipe_question, "Recipe questions must use author order, not priority")
if question_dto_match:
    dto_body = question_dto_match.group(1)
    require(not re.search(r"public let\s+(?:action|advice|hint)\b", dto_body),
            "RecipeQuestionDTO must not require action/advice/hint mappings")

coordinator = coordinator_path.read_text(encoding="utf-8", errors="ignore") if coordinator_path.exists() else ""
for token in [
    "!runtime.questions.isEmpty && !references.isEmpty",
    "runtime.nextQuestion()",
    "currentFrame: payload",
    "references: references",
    "question: question",
    "judge.judge(",
]:
    require(token in coordinator, f"Frame/reference/question scheduling path is missing: {token}")
require("CriticAdvice" not in coordinator and "ActionPresenter" not in coordinator,
        "Question coordinator must not depend on advice/action presentation")

# Structural ablation is the primary architecture release gate.
run([sys.executable, "scripts/run-question-ablation.py"], "v0.9.4 camera-first question-core ablation")

run([sys.executable, "scripts/run-ui-closure-audit.py"], "UI closure audit")

# Unit tests for the two core packages are part of the release gate.
run(["swift", "test", "--package-path", "Packages/GuidanceCore"], "GuidanceCore tests")
run(["swift", "test", "--package-path", "Packages/RecipeKit"], "RecipeKit tests")

# ---- Runtime management + issue-only UI ----------------------------------
view_model = text("Packages/GuidanceUI/GuidanceViewModel.swift")
for token in [
    "skipCurrentQuestion()",
    "setQuestionSkipped(",
    "restoreAllQuestions()",
    "questionCoordinator.schedule(frame: frame)",
    "questionCoordinator.invalidateAnswersPreservingSkips()",
    "setFlashMode(_ target: CameraFlashMode)",
]:
    require(token in view_model, f"Question runtime management is missing: {token}")

question_slice_match = re.search(
    r"private func applyQuestionGuidance\(now: Date\) \{(.*?)\n  private static func makeQuestionJudge",
    view_model,
    re.S,
)
require(question_slice_match is not None, "Unable to inspect question-only UI path")
if question_slice_match:
    question_slice = question_slice_match.group(1)
    require("instruction = L(text)" in question_slice, "Camera must surface Recipe-authored issue text")
    require("currentAction = nil" in question_slice, "Question mode must explicitly clear legacy actions")
    for forbidden in ["CriticAdvice", "ActionPresenter", "往左", "往右", "靠近一点", "退后一点", "拿低", "抬高"]:
        require(forbidden not in question_slice, f"Question UI leaked action generation: {forbidden}")

camera_view = text("Packages/GuidanceUI/CameraCoachView.swift")
for token in [
    'accessibilityIdentifier("camera.skipQuestion")',
    'accessibilityIdentifier("camera.questionManager")',
    'accessibilityIdentifier("camera.recipe")',
    'accessibilityIdentifier("camera.recipeTray")',
    'accessibilityIdentifier("camera.recipeDismiss")',
    'accessibilityIdentifier("camera.recipeManage")',
    'photoguide.camera.gridEnabled.v1',
    'cameraUtilityCluster',
    'setFlashMode(.off)',
    'setFlashMode(.auto)',
    'setFlashMode(.on)',
    'TabView(',
]:
    require(token in camera_view, f"Camera-first question UI is missing: {token}")
for forbidden in [
    'CameraGuidanceLayout',
    'camera.menu',
    'camera.recipeQuick',
    'camera.guidanceLayout',
    'camera.splitGuidancePanel',
    'photoguide.camera.guidanceLayout.v1',
]:
    require(forbidden not in camera_view, f"Removed duplicate/split camera surface leaked back in: {forbidden}")
require(camera_view.count('accessibilityIdentifier("camera.recipe")') == 1,
        "Camera must expose exactly one visible Recipe entry")
require(not (ROOT / "Packages/GuidanceUI/OnboardingView.swift").exists(), "Onboarding page must remain removed")
require(not (ROOT / "Packages/GuidanceUI/ProductSettingsView.swift").exists(), "Standalone settings page must remain removed")
require(not (ROOT / "Packages/GuidanceUI/CameraControlSheet.swift").exists(), "Standalone camera control sheet must remain removed")
root_view = text("Packages/GuidanceUI/RootView.swift")
for token in [
    "GuidanceCameraView(",
    "Recipe 广场",
    "我的 Recipe",
    "创建 Recipe",
    "recipe.favorite.",
    "recipe.manage.",
    "activeRecipeIdentity",
    "updatedAt.timeIntervalSince1970",
    "store.delete(asset.id)",
]:
    require(token in root_view, f"Camera-first root/menu is missing: {token}")
active_slice = root_view.split("private var activeRecipe", 1)[1].split("private static let cameraShellRecipe", 1)[0]
require("RecipeLoader().catalog().map" not in active_slice, "Legacy bundled Recipes must not enter the camera-first runtime")
for forbidden in ["HomeView", "RecipeDetailView", "PhotoGuideOnboardingView", "PhotoGuideSettingsView"]:
    require(forbidden not in root_view, f"Removed page leaked back into root: {forbidden}")

# ---- Recipe asset management ----------------------------------------------
studio = text("Packages/GuidanceUI/RecipeStudio.swift")
for token in [
    "importRecipe",
    "toggleFavorite",
    "RecipeEditorView",
    "PhotosPicker",
    "RecipeFactory.defaultQuestions",
    "must contain at least one question",
    "must contain at least one reference image",
    "删除选项",
    "choices.removeAll",
]:
    require(token in studio, f"Recipe workspace is missing capability/validation: {token}")
require("UserDefaults" in studio, "Recipe assets must persist locally")



ui_tests = text("Tests/PhotoGuideUITests.swift")
for token in [
    'camera.recipe',
    'camera.recipeTray',
    'camera.recipeDismiss',
    'camera.recipeManage',
    'testUnifiedRecipeEntryReachesManagement',
    'testRecipeTrayDismissesBackToFullscreenCamera',
]:
    require(token in ui_tests, f"UI regression contract is missing: {token}")

# ---- Continuous capture: no post-shot workflow ----------------------------
require("CaptureReviewView" not in camera_view, "Capture review must not interrupt continuous capture")
require("CriticReport" not in camera_view, "Critic report must not interrupt continuous capture")
require(not (ROOT / "Packages/GuidanceUI/CaptureReviewView.swift").exists(), "CaptureReviewView.swift must remain removed")
require(not (ROOT / "Packages/GuidanceUI/CriticReportView.swift").exists(), "CriticReportView.swift must remain removed")
capture_match = re.search(r"public func capture\(\) \{(.*?)\n  private var interactiveZoomRange", view_model, re.S)
require(capture_match is not None, "Unable to inspect continuous capture path")
if capture_match:
    capture_body = capture_match.group(1)
    release_pos = capture_body.find("isCapturing = false")
    save_pos = capture_body.find("savePhotoToLibrary(image)")
    require(release_pos >= 0 and save_pos >= 0 and release_pos < save_pos,
            "Shutter must be released before Photo Library persistence")
    require("CaptureReview" not in capture_body and "CriticReport" not in capture_body,
            "Capture must not route into a post-shot surface")

# ---- Docs / generated project --------------------------------------------
for rel in [
    "Docs/RECIPE-QUESTION-CONTRACT-v0.9.1.md",
    "Docs/CHANGELOG-v0.9.4.md",
    "Docs/IMPLEMENTATION-STATUS-v0.9.4.md",
    "Docs/ABLATION-REPORT-v0.9.4.md",
    "Docs/UI-CLOSURE-AUDIT-v0.9.4.md",
]:
    require((ROOT / rel).exists(), f"Missing release document: {rel}")

pbx = ROOT / "PhotoGuide.xcodeproj/project.pbxproj"
require(pbx.exists(), "Generated PhotoGuide.xcodeproj is missing")
if pbx.exists():
    pbx_text = pbx.read_text(encoding="utf-8", errors="ignore")
    for token in [
        "QuestionGuidanceCoordinator.swift",
        "RecipeQuestion.swift",
        "RecipeStudio.swift",
        "PrivacyInfo.xcprivacy",
        "com.guyuedumingx.PhotoGuide",
        "MARKETING_VERSION = 0.9.4",
        "CURRENT_PROJECT_VERSION = 27",
    ]:
        require(token in pbx_text, f"Xcode project is missing {token}")
    run(["plutil", "-lint", str(pbx)], "pbxproj syntax")

scheme = ROOT / "PhotoGuide.xcodeproj/xcshareddata/xcschemes/PhotoGuideApp.xcscheme"
require(scheme.exists(), "Shared PhotoGuideApp scheme is missing")

# Swift syntax across shipping source files. This is not an iOS SDK type-check.
swift_files = [
    str(path)
    for base in shipping_roots
    for path in base.rglob("*.swift")
    if ".build" not in path.parts
]
for path in swift_files:
    proc = subprocess.run(["swiftc", "-parse", path], cwd=ROOT, text=True, capture_output=True)
    if proc.returncode:
        errors.append(f"Swift parse failed: {Path(path).relative_to(ROOT)}\n{proc.stderr}")

# A real DJev accuracy benchmark is deliberately NOT fabricated in this cut.
if args.market_release:
    benchmark = ROOT / "Benchmarks/djev-question-benchmark.jsonl"
    require(benchmark.exists() and benchmark.stat().st_size > 0,
            "Market release requires a real held-out Benchmarks/djev-question-benchmark.jsonl")
else:
    notes.append("DJev frame-vs-reference accuracy benchmark: NOT YET RUN (real model integration required)")

if errors:
    print("RELEASE AUDIT FAILED")
    for error in errors:
        print(f"- {error}")
    raise SystemExit(1)

print("RELEASE AUDIT PASSED")
print(f"- legacy bundled recipes kept parseable: {len(recipe_files)}")
print(f"- Swift files parsed: {len(swift_files)}")
for note in notes:
    print(f"- {note}")
print("- note: iOS SDK type-check, Archive validation, privacy report, simulator UI tests and device QA still require macOS/Xcode")
