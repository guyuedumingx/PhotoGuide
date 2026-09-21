#!/usr/bin/env python3
"""Generate a deterministic PhotoGuide.xcodeproj without external dependencies.

project.yml remains the human-readable project specification. This fallback generator
exists so release archives contain a usable Xcode project even when XcodeGen is not
installed in the build environment.
"""
from __future__ import annotations

import hashlib
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJ = ROOT / "PhotoGuide.xcodeproj"


def oid(key: str) -> str:
    return hashlib.sha1(key.encode()).hexdigest().upper()[:24]


def q(value: str) -> str:
    if value.replace("_", "").replace(".", "").replace("-", "").isalnum() and not value.startswith("-"):
        return value
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


class Objects:
    def __init__(self):
        self.sections: dict[str, list[tuple[str, str, list[str]]]] = {}

    def add(self, section: str, key: str, comment: str, lines: list[str]):
        self.sections.setdefault(section, []).append((key, comment, lines))
        return key

    def render(self) -> str:
        order = [
            "PBXBuildFile", "PBXContainerItemProxy", "PBXCopyFilesBuildPhase", "PBXFileReference",
            "PBXFrameworksBuildPhase", "PBXGroup", "PBXNativeTarget", "PBXProject",
            "PBXResourcesBuildPhase", "PBXSourcesBuildPhase", "PBXTargetDependency",
            "PBXVariantGroup", "XCBuildConfiguration", "XCConfigurationList",
            "XCLocalSwiftPackageReference", "XCSwiftPackageProductDependency",
        ]
        out = []
        for section in order:
            entries = self.sections.get(section, [])
            if not entries:
                continue
            out.append(f"/* Begin {section} section */")
            for key, comment, lines in entries:
                out.append(f"\t\t{key} /* {comment} */ = {{")
                out.append(f"\t\t\tisa = {section};")
                out.extend("\t\t\t" + line for line in lines)
                out.append("\t\t};")
            out.append(f"/* End {section} section */")
            out.append("")
        return "\n".join(out)


obj = Objects()

# ---- Files and groups -----------------------------------------------------
products_group = oid("group:Products")
main_group = oid("group:Main")
app_group = oid("group:App")
camera_group = oid("group:CameraRuntime")
perception_group = oid("group:PerceptionRuntime")
recipe_group = oid("group:RecipeKit")
ui_group = oid("group:GuidanceUI")
tests_group = oid("group:Tests")

product_types = {
    "CameraRuntime": ("wrapper.framework", "CameraRuntime.framework"),
    "PerceptionRuntime": ("wrapper.framework", "PerceptionRuntime.framework"),
    "RecipeKit": ("wrapper.framework", "RecipeKit.framework"),
    "GuidanceUI": ("wrapper.framework", "GuidanceUI.framework"),
    "PhotoGuideApp": ("wrapper.application", "PhotoGuide.app"),
    "RecipeKitTests": ("wrapper.cfbundle", "RecipeKitTests.xctest"),
    "PerceptionRuntimeTests": ("wrapper.cfbundle", "PerceptionRuntimeTests.xctest"),
    "PhotoGuideUITests": ("wrapper.cfbundle", "PhotoGuideUITests.xctest"),
}
product_refs = {}
for name, (ftype, path) in product_types.items():
    rid = oid(f"product:{name}")
    product_refs[name] = rid
    obj.add("PBXFileReference", rid, path, [
        f"explicitFileType = {ftype};", "includeInIndex = 0;", f"path = {q(path)};", "sourceTree = BUILT_PRODUCTS_DIR;"
    ])

# file references helper
file_refs: dict[str, str] = {}
def file_ref(rel: str, file_type: str | None = None, name: str | None = None, source_tree: str = "<group>") -> str:
    key = oid("file:" + rel)
    file_refs[rel] = key
    ext = Path(rel).suffix
    if file_type is None:
        file_type = {
            ".swift": "sourcecode.swift",
            ".json": "text.json",
            ".strings": "text.plist.strings",
            ".xcprivacy": "text.xml",
            ".xcassets": "folder.assetcatalog",
        }.get(ext, "text")
    lines = [f"lastKnownFileType = {file_type};"]
    if name:
        lines.append(f"name = {q(name)};")
    lines += [f"path = {q(rel)};", f"sourceTree = {q(source_tree)};"]
    obj.add("PBXFileReference", key, name or Path(rel).name, lines)
    return key

# Source refs relative to their groups
camera_src = file_ref("CameraRuntime.swift")
perception_src = file_ref("PerceptionRuntime.swift")
recipe_src = file_ref("RecipeKit.swift")
recipe_ablation_src = file_ref("RecipeAblation.swift")
recipe_question_src = file_ref("RecipeQuestion.swift")
ui_sources = sorted([p.name for p in (ROOT / "Packages/GuidanceUI").glob("*.swift")])
ui_src_refs = [file_ref(name) for name in ui_sources]
app_src_refs = [file_ref("PhotoGuideApp.swift")]
test_srcs = ["RecipeKitTests.swift", "PerceptionRuntimeTests.swift", "PhotoGuideUITests.swift"]
test_refs = [file_ref(name) for name in test_srcs]

recipe_resources = sorted([p.name for p in (ROOT / "Packages/RecipeKit/Resources").glob("*.json")])
recipe_res_refs = [file_ref("Resources/" + name) for name in recipe_resources]

# localized resource refs and variant groups
ui_loc_children=[]
for loc in ["en", "zh-Hans", "zh-Hant"]:
    rel=f"Resources/{loc}.lproj/Localizable.strings"
    ui_loc_children.append(file_ref(rel, "text.plist.strings", loc))
ui_variant=oid("variant:GuidanceUI:Localizable")
obj.add("PBXVariantGroup", ui_variant, "Localizable.strings", [
    "children = (", *[f"\t{r} /* {loc} */," for r,loc in zip(ui_loc_children,["en","zh-Hans","zh-Hant"])],
    ");", "name = Localizable.strings;", "sourceTree = \"<group>\";"
])

app_info_children=[]
for loc in ["en", "zh-Hans", "zh-Hant"]:
    rel=f"Resources/{loc}.lproj/InfoPlist.strings"
    app_info_children.append(file_ref(rel, "text.plist.strings", loc))
app_info_variant=oid("variant:App:InfoPlist")
obj.add("PBXVariantGroup", app_info_variant, "InfoPlist.strings", [
    "children = (", *[f"\t{r} /* {loc} */," for r,loc in zip(app_info_children,["en","zh-Hans","zh-Hant"])],
    ");", "name = InfoPlist.strings;", "sourceTree = \"<group>\";"
])
privacy_ref=file_ref("Resources/PrivacyInfo.xcprivacy")
assets_ref=file_ref("Assets.xcassets", "folder.assetcatalog")

# Groups: file refs use paths relative to group path.
def group(gid, comment, path, children):
    lines=["children = ("] + [f"\t{rid} /* {cmt} */," for rid,cmt in children] + [");"]
    if path: lines.append(f"path = {q(path)};")
    lines += ["sourceTree = \"<group>\";"]
    obj.add("PBXGroup", gid, comment, lines)

group(camera_group,"CameraRuntime","Packages/CameraRuntime",[(camera_src,"CameraRuntime.swift")])
group(perception_group,"PerceptionRuntime","Packages/PerceptionRuntime",[(perception_src,"PerceptionRuntime.swift")])
group(recipe_group,"RecipeKit","Packages/RecipeKit",[(recipe_src,"RecipeKit.swift"),(recipe_ablation_src,"RecipeAblation.swift"),(recipe_question_src,"RecipeQuestion.swift")]+[(r,Path(n).name) for r,n in zip(recipe_res_refs,recipe_resources)])
group(ui_group,"GuidanceUI","Packages/GuidanceUI",[(r,n) for r,n in zip(ui_src_refs,ui_sources)]+[(ui_variant,"Localizable.strings")])
group(app_group,"PhotoGuideApp","PhotoGuideApp",[(r,"PhotoGuideApp.swift") for r in app_src_refs]+[(assets_ref,"Assets.xcassets"),(app_info_variant,"InfoPlist.strings"),(privacy_ref,"PrivacyInfo.xcprivacy")])
group(tests_group,"Tests","Tests",[(r,n) for r,n in zip(test_refs,test_srcs)])
group(products_group,"Products",None,[(product_refs[n],product_types[n][1]) for n in product_types])
group(main_group,"PhotoGuide",None,[(app_group,"PhotoGuideApp"),(ui_group,"GuidanceUI"),(camera_group,"CameraRuntime"),(perception_group,"PerceptionRuntime"),(recipe_group,"RecipeKit"),(tests_group,"Tests"),(products_group,"Products")])

# ---- Build files ----------------------------------------------------------
build_files={}
def build_file(label: str, file_ref_id: str | None=None, product_ref: str | None=None, attrs: list[str] | None=None):
    bid=oid("build:"+label)
    lines=[]
    if file_ref_id: lines.append(f"fileRef = {file_ref_id} /* {label.split(' in ')[0]} */;")
    if product_ref: lines.append(f"productRef = {product_ref} /* GuidanceCore */;")
    if attrs: lines.append("settings = {ATTRIBUTES = ("+", ".join(attrs)+", ); };")
    obj.add("PBXBuildFile",bid,label,lines)
    build_files[label]=bid
    return bid

src_builds={}
src_builds["CameraRuntime"]=[build_file("CameraRuntime.swift in Sources",camera_src)]
src_builds["PerceptionRuntime"]=[build_file("PerceptionRuntime.swift in Sources",perception_src)]
src_builds["RecipeKit"]=[
    build_file("RecipeKit.swift in Sources",recipe_src),
    build_file("RecipeAblation.swift in Sources",recipe_ablation_src),
    build_file("RecipeQuestion.swift in Sources",recipe_question_src),
]
src_builds["GuidanceUI"]=[build_file(f"{n} in Sources",r) for n,r in zip(ui_sources,ui_src_refs)]
src_builds["PhotoGuideApp"]=[build_file("PhotoGuideApp.swift in Sources",app_src_refs[0])]
src_builds["RecipeKitTests"]=[build_file("RecipeKitTests.swift in Sources",test_refs[0])]
src_builds["PerceptionRuntimeTests"]=[build_file("PerceptionRuntimeTests.swift in Sources",test_refs[1])]
src_builds["PhotoGuideUITests"]=[build_file("PhotoGuideUITests.swift in Sources",test_refs[2])]

res_builds={
    "CameraRuntime":[],"PerceptionRuntime":[],
    "RecipeKit":[build_file(f"{Path(n).name} in Resources",r) for n,r in zip(recipe_resources,recipe_res_refs)],
    "GuidanceUI":[build_file("Localizable.strings in Resources",ui_variant)],
    "PhotoGuideApp":[build_file("Assets.xcassets in Resources",assets_ref),build_file("InfoPlist.strings in Resources",app_info_variant),build_file("PrivacyInfo.xcprivacy in Resources",privacy_ref)],
    "RecipeKitTests":[],"PerceptionRuntimeTests":[],"PhotoGuideUITests":[],
}

# Package reference/product
pkg_ref=oid("package:GuidanceCore")
obj.add("XCLocalSwiftPackageReference",pkg_ref,'XCLocalSwiftPackageReference "Packages/GuidanceCore"',["relativePath = Packages/GuidanceCore;"])
pkg_products={}

# Framework relationships
target_ids={name:oid("target:"+name) for name in product_types}
framework_deps={
    "CameraRuntime":[],
    "PerceptionRuntime":[("package","GuidanceCore")],
    "RecipeKit":[("package","GuidanceCore")],
    "GuidanceUI":[("target","CameraRuntime"),("target","PerceptionRuntime"),("target","RecipeKit"),("package","GuidanceCore")],
    "PhotoGuideApp":[("target","GuidanceUI"),("target","CameraRuntime"),("target","PerceptionRuntime"),("target","RecipeKit"),("package","GuidanceCore")],
    "RecipeKitTests":[("target","RecipeKit"),("package","GuidanceCore")],
    "PerceptionRuntimeTests":[("target","PerceptionRuntime"),("package","GuidanceCore")],
    "PhotoGuideUITests":[("target","PhotoGuideApp")],
}
framework_builds={n:[] for n in product_types}
for target,deps in framework_deps.items():
    for kind,dep in deps:
        if kind=="package":
            pkg_prod = oid(f"package-product:GuidanceCore:{target}")
            pkg_products[target] = pkg_prod
            obj.add("XCSwiftPackageProductDependency",pkg_prod,f"GuidanceCore ({target})",["productName = GuidanceCore;"])
            bid=build_file(f"GuidanceCore in Frameworks ({target})",product_ref=pkg_prod)
        else:
            if product_types[dep][0] != "wrapper.framework":
                continue
            bid=build_file(f"{dep}.framework in Frameworks ({target})",file_ref_id=product_refs[dep])
        framework_builds[target].append(bid)

# Build phases
source_phases={}; resource_phases={}; framework_phases={}; embed_phases={}
def phase(section, target, kind, files, extra=None):
    pid=oid(f"phase:{target}:{kind}")
    lines=["buildActionMask = 2147483647;", "files = ("] + [f"\t{x}," for x in files] + [");", "runOnlyForDeploymentPostprocessing = 0;"]
    if extra: lines=extra[:1]+lines+extra[1:]
    obj.add(section,pid,f"{kind} ({target})",lines)
    return pid

for target in product_types:
    source_phases[target]=phase("PBXSourcesBuildPhase",target,"Sources",src_builds[target])
    framework_phases[target]=phase("PBXFrameworksBuildPhase",target,"Frameworks",framework_builds[target])
    resource_phases[target]=phase("PBXResourcesBuildPhase",target,"Resources",res_builds[target])

# Embed framework build files in app
embed_files=[]
for dep in ["GuidanceUI","CameraRuntime","PerceptionRuntime","RecipeKit"]:
    embed_files.append(build_file(f"{dep}.framework in Embed Frameworks",file_ref_id=product_refs[dep],attrs=["CodeSignOnCopy","RemoveHeadersOnCopy"]))
embed_id=oid("phase:PhotoGuideApp:Embed Frameworks")
obj.add("PBXCopyFilesBuildPhase",embed_id,"Embed Frameworks",[
    "buildActionMask = 2147483647;","dstPath = \"\";","dstSubfolderSpec = 10;","files = (",*[f"\t{x}," for x in embed_files],");","name = \"Embed Frameworks\";","runOnlyForDeploymentPostprocessing = 0;"
])
embed_phases["PhotoGuideApp"]=embed_id

# Target dependencies/proxies
target_dependency_ids={n:[] for n in product_types}
for target,deps in framework_deps.items():
    for kind,dep in deps:
        if kind != "target": continue
        proxy=oid(f"proxy:{target}:{dep}")
        obj.add("PBXContainerItemProxy",proxy,f"PBXContainerItemProxy ({target} -> {dep})",[
            f"containerPortal = {oid('project')} /* Project object */;","proxyType = 1;",f"remoteGlobalIDString = {target_ids[dep]};",f"remoteInfo = {q(dep)};"
        ])
        td=oid(f"target-dependency:{target}:{dep}")
        obj.add("PBXTargetDependency",td,dep,[f"target = {target_ids[dep]} /* {dep} */;",f"targetProxy = {proxy} /* PBXContainerItemProxy ({target} -> {dep}) */;"])
        target_dependency_ids[target].append(td)

# Build configurations
project_debug=oid("config:project:Debug"); project_release=oid("config:project:Release")
base_project={
    "CLANG_ENABLE_MODULES":"YES","IPHONEOS_DEPLOYMENT_TARGET":"18.0","SDKROOT":"iphoneos","SWIFT_STRICT_CONCURRENCY":"complete","SWIFT_VERSION":"6.0","TARGETED_DEVICE_FAMILY":"1","SUPPORTS_MACCATALYST":"NO"
}
def config(cid, comment, settings):
    lines=["buildSettings = {"]
    for k,v in settings.items(): lines.append(f"\t{k} = {q(str(v))};")
    lines += ["};",f"name = {comment};"]
    obj.add("XCBuildConfiguration",cid,comment,lines)

config(project_debug,"Debug",base_project|{"DEBUG_INFORMATION_FORMAT":"dwarf","ONLY_ACTIVE_ARCH":"YES","SWIFT_ACTIVE_COMPILATION_CONDITIONS":"DEBUG"})
config(project_release,"Release",base_project|{"DEBUG_INFORMATION_FORMAT":"dwarf-with-dsym","SWIFT_COMPILATION_MODE":"wholemodule","VALIDATE_PRODUCT":"YES"})

config_lists={}
proj_cfg_list=oid("configlist:project")
obj.add("XCConfigurationList",proj_cfg_list,"Build configuration list for PBXProject \"PhotoGuide\"",[
    "buildConfigurations = (",f"\t{project_debug} /* Debug */,",f"\t{project_release} /* Release */,",");","defaultConfigurationIsVisible = 0;","defaultConfigurationName = Release;"
])

def target_settings(name, debug):
    base={
      "CODE_SIGN_STYLE":"Automatic","GENERATE_INFOPLIST_FILE":"YES","PRODUCT_NAME": name if name!="PhotoGuideApp" else "PhotoGuide",
      "SKIP_INSTALL":"YES" if name!="PhotoGuideApp" else "NO",
    }
    bundle={
      "CameraRuntime":"com.photoguide.CameraRuntime","PerceptionRuntime":"com.photoguide.PerceptionRuntime","RecipeKit":"com.photoguide.RecipeKit","GuidanceUI":"com.photoguide.GuidanceUI",
      "PhotoGuideApp":"com.guyuedumingx.PhotoGuide","RecipeKitTests":"com.photoguide.RecipeKitTests","PerceptionRuntimeTests":"com.photoguide.PerceptionRuntimeTests","PhotoGuideUITests":"com.photoguide.PhotoGuideUITests"
    }[name]
    base["PRODUCT_BUNDLE_IDENTIFIER"]=bundle
    if name in ("RecipeKitTests","PerceptionRuntimeTests","PhotoGuideUITests"):
        base["CODE_SIGNING_ALLOWED"]="NO"
    if name=="PhotoGuideUITests": base["TEST_TARGET_NAME"]="PhotoGuideApp"
    if name=="PhotoGuideApp":
        base.update({
          "MARKETING_VERSION":"0.9.4","CURRENT_PROJECT_VERSION":"27","INFOPLIST_KEY_CFBundleDisplayName":"PhotoGuide","INFOPLIST_KEY_CFBundleDevelopmentRegion":"en",
          "MULTIMODAL_CRITIC_ENDPOINT":"","INFOPLIST_KEY_MultimodalCriticEndpoint":"$(MULTIMODAL_CRITIC_ENDPOINT)",
          "DJEV_ENDPOINT":"","INFOPLIST_KEY_DJEVEndpoint":"$(DJEV_ENDPOINT)",
          "INFOPLIST_KEY_NSCameraUsageDescription":"PhotoGuide uses the camera for live framing analysis and real-time shooting guidance.",
          "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription":"PhotoGuide needs permission to save captured photos to your Photo Library.",
          "INFOPLIST_KEY_UIRequiresFullScreen":"YES","INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone":"UIInterfaceOrientationPortrait",
          "INFOPLIST_KEY_UIStatusBarStyle":"UIStatusBarStyleLightContent","INFOPLIST_KEY_UILaunchScreen_Generation":"YES",
          "INFOPLIST_KEY_LSApplicationCategoryType":"public.app-category.photography","ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon","ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME":"AccentColor",
        })
    if debug: base["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]="DEBUG"
    return base

for name in product_types:
    dbg=oid(f"config:{name}:Debug"); rel=oid(f"config:{name}:Release")
    config(dbg,"Debug",target_settings(name,True)); config(rel,"Release",target_settings(name,False))
    cl=oid(f"configlist:{name}"); config_lists[name]=cl
    obj.add("XCConfigurationList",cl,f"Build configuration list for PBXNativeTarget \"{name}\"",[
        "buildConfigurations = (",f"\t{dbg} /* Debug */,",f"\t{rel} /* Release */,",");","defaultConfigurationIsVisible = 0;","defaultConfigurationName = Release;"
    ])

# Native targets
ptype={
 "CameraRuntime":"com.apple.product-type.framework","PerceptionRuntime":"com.apple.product-type.framework","RecipeKit":"com.apple.product-type.framework","GuidanceUI":"com.apple.product-type.framework",
 "PhotoGuideApp":"com.apple.product-type.application","RecipeKitTests":"com.apple.product-type.bundle.unit-test","PerceptionRuntimeTests":"com.apple.product-type.bundle.unit-test","PhotoGuideUITests":"com.apple.product-type.bundle.ui-testing"
}
for name in product_types:
    phases=[source_phases[name],framework_phases[name],resource_phases[name]]
    if name in embed_phases: phases.append(embed_phases[name])
    pkgdeps=[]
    if name in pkg_products: pkgdeps=[pkg_products[name]]
    lines=[
      f"buildConfigurationList = {config_lists[name]} /* Build configuration list for PBXNativeTarget \"{name}\" */;",
      "buildPhases = (",*[f"\t{x}," for x in phases],");","buildRules = ();",
      "dependencies = (",*[f"\t{x}," for x in target_dependency_ids[name]],");",
      f"name = {q(name)};",
      "packageProductDependencies = (",*[f"\t{x} /* GuidanceCore */," for x in pkgdeps],");",
      f"productName = {q(name if name!='PhotoGuideApp' else 'PhotoGuide')};",f"productReference = {product_refs[name]} /* {product_types[name][1]} */;",f"productType = {q(ptype[name])};"
    ]
    obj.add("PBXNativeTarget",target_ids[name],name,lines)

# Project
project_id=oid("project")
target_attr=" ".join([])
obj.add("PBXProject",project_id,"Project object",[
  f"buildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject \"PhotoGuide\" */;",
  "compatibilityVersion = \"Xcode 15.0\";","developmentRegion = en;","hasScannedForEncodings = 0;","knownRegions = (en, Base, \"zh-Hans\", \"zh-Hant\");",
  f"mainGroup = {main_group};",f"packageReferences = ( {pkg_ref} /* XCLocalSwiftPackageReference \"Packages/GuidanceCore\" */, );",f"productRefGroup = {products_group} /* Products */;","projectDirPath = \"\";","projectRoot = \"\";",
  "targets = (",*[f"\t{target_ids[n]} /* {n} */," for n in product_types],");"
])

pbx = """// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 60;\n\tobjects = {\n\n""" + obj.render() + f"\t}};\n\trootObject = {project_id} /* Project object */;\n}}\n"

if PROJ.exists(): shutil.rmtree(PROJ)
(PROJ / "project.xcworkspace").mkdir(parents=True)
(PROJ / "xcshareddata/xcschemes").mkdir(parents=True)
(PROJ / "project.pbxproj").write_text(pbx)
(PROJ / "project.xcworkspace/contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')

# Shared scheme
scheme= f'''<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="1600" version="1.7">\n  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">\n    <BuildActionEntries>\n      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">\n        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids['PhotoGuideApp']}" BuildableName="PhotoGuide.app" BlueprintName="PhotoGuideApp" ReferencedContainer="container:PhotoGuide.xcodeproj"/>\n      </BuildActionEntry>\n    </BuildActionEntries>\n  </BuildAction>\n  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">\n    <Testables>\n'''
for n in ["RecipeKitTests","PerceptionRuntimeTests","PhotoGuideUITests"]:
    scheme += f'''      <TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids[n]}" BuildableName="{product_types[n][1]}" BlueprintName="{n}" ReferencedContainer="container:PhotoGuide.xcodeproj"/></TestableReference>\n'''
scheme += f'''    </Testables>\n  </TestAction>\n  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">\n    <BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids['PhotoGuideApp']}" BuildableName="PhotoGuide.app" BlueprintName="PhotoGuideApp" ReferencedContainer="container:PhotoGuide.xcodeproj"/></BuildableProductRunnable>\n  </LaunchAction>\n  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_ids['PhotoGuideApp']}" BuildableName="PhotoGuide.app" BlueprintName="PhotoGuideApp" ReferencedContainer="container:PhotoGuide.xcodeproj"/></BuildableProductRunnable></ProfileAction>\n  <AnalyzeAction buildConfiguration="Debug"/>\n  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>\n</Scheme>\n'''
(PROJ / "xcshareddata/xcschemes/PhotoGuideApp.xcscheme").write_text(scheme)
print(f"Generated {PROJ}")
print(f"GuidanceUI sources: {len(ui_sources)}; recipes: {len(recipe_resources)}")
