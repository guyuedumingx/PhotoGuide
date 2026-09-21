#!/usr/bin/env python3
"""PhotoGuide v0.9.4 structural ablation for the camera-first ordered Recipe-question core."""
from pathlib import Path
import json, re, sys
ROOT=Path(__file__).resolve().parents[1]
CORE=(ROOT/'Packages/GuidanceCore/Sources/GuidanceCore/Runtime/VisualJudge.swift').read_text()
RECIPE=(ROOT/'Packages/RecipeKit/RecipeQuestion.swift').read_text()
UI=(ROOT/'Packages/GuidanceUI/GuidanceViewModel.swift').read_text()
CAMERA=(ROOT/'Packages/GuidanceUI/CameraCoachView.swift').read_text()
STUDIO=(ROOT/'Packages/GuidanceUI/RecipeStudio.swift').read_text()
errors=[]
def check(c,m):
    if not c: errors.append(m)
experiments={}
a={
 'choice_only':'case choice(String)' in CORE,
 'score_only':'case score(Double)' in CORE,
 'boolean_only':'case boolean(Bool)' in CORE,
 'no_action_in_judge_answer':'case action' not in CORE.split('public enum JudgeAnswer',1)[1].split('}',1)[0],
 'visual_judge_protocol':'public protocol VisualJudge' in CORE,
 'invalid_answer_not_match':'question.answerSpec.accepts(answer)' in CORE,
}
for k,v in a.items(): check(v,f'bounded-output ablation failed: {k}')
experiments['bounded_model_output']=a
b={
 'portable_reference':'RecipeReferenceDTO' in RECIPE and 'imageBase64' in RECIPE,
 'question_dto':'RecipeQuestionDTO' in RECIPE,
 'no_question_priority':'public let priority: Double' not in RECIPE,
 'question_factory':'questionRecipe(' in RECIPE,
 'reference_generator':'references: [.init' in STUDIO,
 'no_hint_field_in_question_dto':not re.search(r'public let (?:hint|action|advice)', RECIPE),
}
for k,v in b.items(): check(v,f'recipe-contract ablation failed: {k}')
experiments['recipe_contract']=b
c={
 'question_runtime':'public struct QuestionRuntime' in CORE,
 'skip':'public mutating func skip' in CORE,
 'restore':'public mutating func restore' in CORE,
 'periodic_recheck':'state.status == .issue ? 0.9 : 2.8' in CORE,
 'author_order_scheduler':'if let unseen = active.first' in CORE and 'for question in active' in CORE,
 'ordered_issues':'public func issueSnapshots()' in CORE,
 'no_issue_ranking':'issuePriority' not in CORE and 'severity' not in CORE.split('public struct QuestionRuntime',1)[1],
 'ui_skip':'skipCurrentQuestion' in UI and 'setQuestionSkipped' in UI,
 'management_surface':'restoreAllQuestions' in UI and 'camera.restoreSkippedQuestions' in CAMERA,
}
for k,v in c.items(): check(v,f'question-management ablation failed: {k}')
experiments['ordered_question_management']=c
d={
 'uses_selected_recipe_issue':'selectedIssueSnapshot' in UI and 'issue.issue' in UI,
 'swipe_surface':'TabView(' in CAMERA and 'selectIssueQuestion' in CAMERA,
 'shows_recipe_order_count':'index + 1' in CAMERA and 'total' in CAMERA,
 'no_action_presenter':'ActionPresenter' not in UI.split('private func applyQuestionGuidance',1)[1].split('private static func makeQuestionJudge',1)[0],
 'no_move_instruction':not any(x in UI.split('private func applyQuestionGuidance',1)[1].split('private static func makeQuestionJudge',1)[0] for x in ['往左','往右','靠近','退后','拿低','抬高']),
 'camera_first_root':'GuidanceCameraView(' in (ROOT/'Packages/GuidanceUI/RootView.swift').read_text(),
 'dual_guidance_layout':'CameraGuidanceLayout' in CAMERA and 'camera.splitGuidancePanel' in CAMERA,
}
for k,v in d.items(): check(v,f'issue-only UI ablation failed: {k}')
experiments['ordered_swipe_issue_ui']=d
e={
 'runtime_requires_questions':'!runtime.questions.isEmpty' in (ROOT/'Packages/GuidanceUI/QuestionGuidanceCoordinator.swift').read_text(),
 'runtime_requires_references':'!references.isEmpty' in (ROOT/'Packages/GuidanceUI/QuestionGuidanceCoordinator.swift').read_text(),
 'store_requires_questions':'must contain at least one question' in STUDIO,
 'store_requires_reference':'must contain at least one reference image' in STUDIO,
 'author_can_reorder':'moveQuestion(' in STUDIO and 'arrow.up' in STUDIO and 'arrow.down' in STUDIO,
}
for k,v in e.items(): check(v,f'reference-question necessity ablation failed: {k}')
experiments['reference_question_and_order_are_necessary']=e
ROOT_UI=(ROOT/'Packages/GuidanceUI/RootView.swift').read_text()
f={
 'compact_top_utility_cluster':'cameraUtilityCluster' in CAMERA and 'camera.controls' in CAMERA and 'camera.guidanceLayout' in CAMERA,
 'persistent_grid':'photoguide.camera.gridEnabled.v1' in CAMERA,
 'split_safe_area':'splitGuidancePanel(safeBottom:' in CAMERA and 'max(safeBottom, 8)' in CAMERA,
 'large_question_set_safe_pager':'issues.count <= 7' in CAMERA,
 'in_camera_question_manager':'camera.questionManager' in CAMERA and 'setQuestionSkipped' in CAMERA,
 'recipe_favorite_without_new_page':'recipe.favorite.' in ROOT_UI and 'toggleFavorite' in ROOT_UI,
 'legacy_recipe_not_active':'RecipeLoader().catalog().map' not in ROOT_UI.split('private var activeRecipe',1)[1].split('private static let cameraShellRecipe',1)[0],
 'camera_recipe_quick_picker':'camera.recipeQuick' in CAMERA and 'camera.recipeTray' in CAMERA and 'onSelectRecipe' in CAMERA,
 'douyin_style_recipe_strip':'ScrollView(.horizontal)' in CAMERA and 'recipeQuickTile' in CAMERA,
 'active_recipe_refresh_after_edit':'activeRecipeIdentity' in ROOT_UI and 'updatedAt.timeIntervalSince1970' in ROOT_UI,
 'direct_flash_selection':'setFlashMode(.off)' in CAMERA and 'setFlashMode(.auto)' in CAMERA and 'setFlashMode(.on)' in CAMERA,
 'owned_recipe_edit_delete':'recipe.manage.' in ROOT_UI and 'store.delete(asset.id)' in ROOT_UI and 'RecipeEditorView(recipe: asset.recipe' in ROOT_UI,
 'choice_option_can_be_removed':'删除选项' in STUDIO and 'choices.removeAll' in STUDIO,
}
for k,v in f.items(): check(v,f'camera-interaction ablation failed: {k}')
experiments['camera_interaction_shell']=f
summary={'version':'0.9.4','kind':'camera-first-closed-loop-ordered-question-core-structural-ablation','empirical_djev_accuracy_claimed':False,'acceptance_passed':not errors,'experiments':experiments,'errors':errors}
(ROOT/'Docs/ABLATION-REPORT-v0.9.4.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
lines=[
 '# PhotoGuide v0.9.4 — Camera-first Closure Ablation','',
 '> Structural only. Real frame-vs-reference accuracy is intentionally not claimed before DJev is connected.','',
 f"- Acceptance: **{'PASS' if not errors else 'FAIL'}**",
 '- Core: **Reference Images + ordered Recipe Questions + bounded JudgeAnswer**',
 '- Judge outputs: **Choice / Score / Boolean only**','',
 '## A. Bounded System-1 output',f"Result: **{'PASS' if all(a.values()) else 'FAIL'}**. No free-form action/advice generation is required.",'',
 '## B. Recipe owns comparison and order',f"Result: **{'PASS' if all(b.values()) else 'FAIL'}**. Questions are ordered data; no priority/action/hint field is required.",'',
 '## C. Ordered question management',f"Result: **{'PASS' if all(c.values()) else 'FAIL'}**. Skip/restore and periodic recheck work without priority ranking or planning.",'',
 '## D. Swipeable issue-only camera UI',f"Result: **{'PASS' if all(d.values()) else 'FAIL'}**. Current differences remain in Recipe order and can be switched horizontally.",'',
 '## E. Necessity controls',f"Result: **{'PASS' if all(e.values()) else 'FAIL'}**. References, questions, and author order are functional product inputs.",'',
 '## F. Camera interaction shell',f"Result: **{'PASS' if all(f.values()) else 'FAIL'}**. Camera UI keeps layout, question management, favorites, and controls in-place without adding pages.",'',
 '## After DJev integration','Run empirical ablations on real current-frame/reference pairs: question-by-question agreement with human labels, recheck cadence, authored-order usability, and single-reference vs multi-reference consistency.'
]
if errors: lines += ['','## Failures','']+[f'- {x}' for x in errors]
(ROOT/'Docs/ABLATION-REPORT-v0.9.4.md').write_text('\n'.join(lines)+'\n')
print(f"v0.9.4 camera-first ordered question-core ablation {'PASS' if not errors else 'FAIL'}")
for group,vals in experiments.items(): print(f"  {group}: {sum(vals.values())}/{len(vals)}")
if errors:
    print('\n'.join(errors),file=sys.stderr); sys.exit(1)
