#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
CAMERA = (ROOT / 'Packages/GuidanceUI/CameraCoachView.swift').read_text(encoding='utf-8')
ROOT_UI = (ROOT / 'Packages/GuidanceUI/RootView.swift').read_text(encoding='utf-8')
STUDIO = (ROOT / 'Packages/GuidanceUI/RecipeStudio.swift').read_text(encoding='utf-8')
VM = (ROOT / 'Packages/GuidanceUI/GuidanceViewModel.swift').read_text(encoding='utf-8')
TESTS = (ROOT / 'Tests/PhotoGuideUITests.swift').read_text(encoding='utf-8')

checks = {
    # Camera primary loop
    'camera_single_recipe_entry': CAMERA.count('accessibilityIdentifier("camera.recipe")') == 1 and 'camera.menu' not in CAMERA and 'camera.recipeQuick' not in CAMERA,
    'camera_recipe_bottom_tray': 'accessibilityIdentifier("camera.recipeTray")' in CAMERA and 'accessibilityIdentifier("camera.recipeDismiss")' in CAMERA and 'recipeQuickTile' in CAMERA,
    'camera_recipe_select_callback': 'onSelectRecipe(recipe)' in CAMERA and 'onSelectRecipe: { recipe in activeRecipeID = recipe.id }' in ROOT_UI,
    'camera_shutter': 'accessibilityIdentifier("camera.shutter")' in CAMERA and 'model.capture()' in CAMERA,
    'camera_switch': 'accessibilityIdentifier("camera.switch")' in CAMERA and 'model.switchCamera()' in CAMERA,
    'camera_lens': 'model.setZoom(factor)' in CAMERA,
    'camera_fullscreen_layout': '.ignoresSafeArea()' in CAMERA and 'CameraGuidanceLayout' not in CAMERA and 'camera.splitGuidancePanel' not in CAMERA,
    'camera_flash_direct_modes': all(x in CAMERA for x in ['setFlashMode(.off)', 'setFlashMode(.auto)', 'setFlashMode(.on)']),
    'camera_grid_persistent': 'photoguide.camera.gridEnabled.v1' in CAMERA and 'gridEnabled.toggle()' in CAMERA,
    'camera_permission_recovery': 'Button(L("打开设置"), action: model.openSettings)' in CAMERA,
    # Question loop
    'question_swipe': 'TabView(' in CAMERA and 'model.selectIssueQuestion(id)' in CAMERA,
    'question_skip': 'accessibilityIdentifier("camera.skipQuestion")' in CAMERA and 'model.skipCurrentQuestion()' in CAMERA,
    'question_restore': 'restoreAllQuestions()' in CAMERA and 'setQuestionSkipped' in CAMERA,
    'question_manager': 'accessibilityIdentifier("camera.questionManager")' in CAMERA,
    # Capture continuity
    'capture_release_before_save': VM.find('isCapturing = false', VM.find('public func capture()')) < VM.find('savePhotoToLibrary(image)', VM.find('public func capture()')),
    'no_post_capture_report': 'CaptureReviewView' not in CAMERA and 'CriticReport' not in CAMERA,
    # Recipe management
    'menu_three_surfaces': all(x in ROOT_UI for x in ['Recipe 广场', '我的 Recipe', '创建 Recipe']),
    'recipe_favorite': 'recipe.favorite.' in ROOT_UI and 'toggleFavorite' in ROOT_UI,
    'recipe_edit': 'RecipeEditorView(recipe: asset.recipe' in ROOT_UI and 'recipe.manage.' in ROOT_UI,
    'recipe_delete': 'store.delete(asset.id)' in ROOT_UI and '删除 Recipe？' in ROOT_UI,
    'active_recipe_refresh_after_edit': 'activeRecipeIdentity' in ROOT_UI and 'updatedAt.timeIntervalSince1970' in ROOT_UI,
    'create_from_reference': 'PhotosPicker(selection: $selectedPhotoItem' in ROOT_UI,
    'create_blank': 'showBlankEditor = true' in ROOT_UI,
    'import_json': 'fileImporter' in ROOT_UI and 'store.importRecipe' in ROOT_UI,
    # Recipe editor
    'editor_reference_add_remove': 'model.addReference(image)' in STUDIO and 'model.removeReference(reference.id)' in STUDIO,
    'editor_question_add_remove': 'model.addQuestion' in STUDIO and 'model.removeQuestion' in STUDIO,
    'editor_question_reorder': 'moveQuestion' in STUDIO and '.disabled(isFirst)' in STUDIO and '.disabled(isLast)' in STUDIO,
    'editor_choice_add_remove': '添加选项' in STUDIO and 'choices.removeAll' in STUDIO and '删除选项' in STUDIO,
    'editor_save': 'store.save(model.makeRecipe()' in STUDIO,
    'editor_cancel': 'Button(L("取消")) { dismiss() }' in STUDIO,
    # Regression coverage
    'ui_test_unified_recipe_entry': 'testUnifiedRecipeEntryReachesManagement' in TESTS and 'testRecipeTrayDismissesBackToFullscreenCamera' in TESTS and 'camera.recipeTray' in TESTS,
    # Product boundary
    'no_home': 'HomeView' not in ROOT_UI,
    'no_recipe_detail': 'RecipeDetailView' not in ROOT_UI,
    'no_settings_page': 'PhotoGuideSettingsView' not in ROOT_UI,
    'no_priority': 'priority' not in (ROOT / 'Packages/RecipeKit/RecipeQuestion.swift').read_text(encoding='utf-8').split('public struct RecipeQuestionDTO', 1)[1].split('public enum RecipeQuestionValidationError', 1)[0],
}

failed = [name for name, ok in checks.items() if not ok]
print(f"UI closure audit: {len(checks) - len(failed)}/{len(checks)} PASS")
for name, ok in checks.items():
    print(f"  {'PASS' if ok else 'FAIL'}  {name}")
if failed:
    sys.exit(1)
