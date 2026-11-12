#!/usr/bin/env python3
"""Generate AnyPaste.xcodeproj from the on-disk source tree.

Keeping the project file generated means the id soup stays correct: adding or
removing a Swift file only requires re-running this script.
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(ROOT, "AnyPaste")
PROJECT_DIR = os.path.join(ROOT, "AnyPaste.xcodeproj")

BUNDLE_ID = "com.anypaste.mac"
PRODUCT = "AnyPaste"

GROUPS = {
    "App": ["main.swift", "AppDelegate.swift", "AppMenu.swift"],
    "Core": [
        "AppInfo.swift",
        "Prefs.swift",
        "KeyboardLayout.swift",
        "KeystrokePlanner.swift",
        "KeystrokeTyper.swift",
        "HotKeyManager.swift",
        "ClipboardService.swift",
        "PermissionService.swift",
        "LaunchAtLogin.swift",
        "AppController.swift",
        "Diagnostics.swift",
    ],
    "UI": [
        "HUDWindow.swift",
        "AppWindows.swift",
        "StatusItemController.swift",
        "SettingsView.swift",
        "HotKeySettingsTab.swift",
        "OnboardingView.swift",
    ],
}

RESOURCES = ["AppIcon.icns"]


def oid(key):
    return hashlib.md5(key.encode("utf-8")).hexdigest().upper()[:24]


def main():
    missing = []
    for group, files in GROUPS.items():
        for name in files:
            path = os.path.join(APP_DIR, group, name)
            if not os.path.isfile(path):
                missing.append(path)
    for name in RESOURCES:
        path = os.path.join(APP_DIR, "Resources", name)
        if not os.path.isfile(path):
            missing.append(path)
    if missing:
        raise SystemExit("missing files:\n  " + "\n  ".join(missing))

    ids = {}
    ids["project"] = oid("project")
    ids["main_group"] = oid("main_group")
    ids["app_group"] = oid("app_group")
    ids["products_group"] = oid("products_group")
    ids["sources_phase"] = oid("sources_phase")
    ids["resources_phase"] = oid("resources_phase")
    ids["frameworks_phase"] = oid("frameworks_phase")
    ids["target"] = oid("target")
    ids["project_config_list"] = oid("project_config_list")
    ids["target_config_list"] = oid("target_config_list")
    ids["project_debug"] = oid("project_debug")
    ids["project_release"] = oid("project_release")
    ids["target_debug"] = oid("target_debug")
    ids["target_release"] = oid("target_release")
    ids["product_ref"] = oid("product_ref")
    ids["info_plist_ref"] = oid("info_plist_ref")

    source_entries = []       # (group, name, file_ref, build_file)
    for group, files in GROUPS.items():
        for name in files:
            key = "%s/%s" % (group, name)
            source_entries.append(
                (group, name, oid("fileref:" + key), oid("buildfile:" + key))
            )

    resource_entries = [(name, oid("fileref:res:" + name), oid("buildfile:res:" + name)) for name in RESOURCES]

    lines = []
    add = lines.append

    add("// !$*UTF8*$!")
    add("{")
    add("\tarchiveVersion = 1;")
    add("\tclasses = {")
    add("\t};")
    add("\tobjectVersion = 56;")
    add("\tobjects = {")
    add("")

    # PBXBuildFile
    add("/* Begin PBXBuildFile section */")
    for group, name, file_ref, build_file in source_entries:
        add(
            "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
            % (build_file, name, file_ref, name)
        )
    for name, file_ref, build_file in resource_entries:
        add(
            "\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
            % (build_file, name, file_ref, name)
        )
    add("/* End PBXBuildFile section */")
    add("")

    # PBXFileReference
    add("/* Begin PBXFileReference section */")
    add(
        "\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; "
        "includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };"
        % (ids["product_ref"], PRODUCT, PRODUCT)
    )
    add(
        "\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; "
        "path = Info.plist; sourceTree = \"<group>\"; };" % ids["info_plist_ref"]
    )
    for group, name, file_ref, _ in source_entries:
        add(
            "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            "path = %s; sourceTree = \"<group>\"; };" % (file_ref, name, name)
        )
    for name, file_ref, _ in resource_entries:
        add(
            "\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = image.icns; "
            "path = %s; sourceTree = \"<group>\"; };" % (file_ref, name, name)
        )
    add("/* End PBXFileReference section */")
    add("")

    # PBXFrameworksBuildPhase
    add("/* Begin PBXFrameworksBuildPhase section */")
    add("\t\t%s /* Frameworks */ = {" % ids["frameworks_phase"])
    add("\t\t\tisa = PBXFrameworksBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXFrameworksBuildPhase section */")
    add("")

    # PBXGroup
    add("/* Begin PBXGroup section */")
    add("\t\t%s = {" % ids["main_group"])
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add("\t\t\t\t%s /* AnyPaste */," % ids["app_group"])
    add("\t\t\t\t%s /* Products */," % ids["products_group"])
    add("\t\t\t);")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add("\t\t%s /* AnyPaste */ = {" % ids["app_group"])
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    for group in GROUPS:
        add("\t\t\t\t%s /* %s */," % (oid("group:" + group), group))
    add("\t\t\t\t%s /* Resources */," % oid("group:Resources"))
    add("\t\t\t\t%s /* Info.plist */," % ids["info_plist_ref"])
    add("\t\t\t);")
    add("\t\t\tpath = AnyPaste;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    for group, files in GROUPS.items():
        add("\t\t%s /* %s */ = {" % (oid("group:" + group), group))
        add("\t\t\tisa = PBXGroup;")
        add("\t\t\tchildren = (")
        for entry_group, entry_name, entry_ref, _ in source_entries:
            if entry_group != group:
                continue
            add("\t\t\t\t%s /* %s */," % (entry_ref, entry_name))
        add("\t\t\t);")
        add("\t\t\tpath = %s;" % group)
        add("\t\t\tsourceTree = \"<group>\";")
        add("\t\t};")

    add("\t\t%s /* Resources */ = {" % oid("group:Resources"))
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    for name, file_ref, _ in resource_entries:
        add("\t\t\t\t%s /* %s */," % (file_ref, name))
    add("\t\t\t);")
    add("\t\t\tpath = Resources;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")

    add("\t\t%s /* Products */ = {" % ids["products_group"])
    add("\t\t\tisa = PBXGroup;")
    add("\t\t\tchildren = (")
    add("\t\t\t\t%s /* %s.app */," % (ids["product_ref"], PRODUCT))
    add("\t\t\t);")
    add("\t\t\tname = Products;")
    add("\t\t\tsourceTree = \"<group>\";")
    add("\t\t};")
    add("/* End PBXGroup section */")
    add("")

    # PBXNativeTarget
    add("/* Begin PBXNativeTarget section */")
    add("\t\t%s /* %s */ = {" % (ids["target"], PRODUCT))
    add("\t\t\tisa = PBXNativeTarget;")
    add("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"%s\" */;"
        % (ids["target_config_list"], PRODUCT))
    add("\t\t\tbuildPhases = (")
    add("\t\t\t\t%s /* Sources */," % ids["sources_phase"])
    add("\t\t\t\t%s /* Frameworks */," % ids["frameworks_phase"])
    add("\t\t\t\t%s /* Resources */," % ids["resources_phase"])
    add("\t\t\t);")
    add("\t\t\tbuildRules = (")
    add("\t\t\t);")
    add("\t\t\tdependencies = (")
    add("\t\t\t);")
    add("\t\t\tname = %s;" % PRODUCT)
    add("\t\t\tproductName = %s;" % PRODUCT)
    add("\t\t\tproductReference = %s /* %s.app */;" % (ids["product_ref"], PRODUCT))
    add("\t\t\tproductType = \"com.apple.product-type.application\";")
    add("\t\t};")
    add("/* End PBXNativeTarget section */")
    add("")

    # PBXProject
    add("/* Begin PBXProject section */")
    add("\t\t%s /* Project object */ = {" % ids["project"])
    add("\t\t\tisa = PBXProject;")
    add("\t\t\tattributes = {")
    add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    add("\t\t\t\tLastUpgradeCheck = 1500;")
    add("\t\t\t\tTargetAttributes = {")
    add("\t\t\t\t\t%s = {" % ids["target"])
    add("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    add("\t\t\t\t\t};")
    add("\t\t\t\t};")
    add("\t\t\t};")
    add("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"%s\" */;"
        % (ids["project_config_list"], PRODUCT))
    add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    add("\t\t\tdevelopmentRegion = en;")
    add("\t\t\thasScannedForEncodings = 0;")
    add("\t\t\tknownRegions = (")
    add("\t\t\t\ten,")
    add("\t\t\t\tBase,")
    add("\t\t\t);")
    add("\t\t\tmainGroup = %s;" % ids["main_group"])
    add("\t\t\tproductRefGroup = %s /* Products */;" % ids["products_group"])
    add("\t\t\tprojectDirPath = \"\";")
    add("\t\t\tprojectRoot = \"\";")
    add("\t\t\ttargets = (")
    add("\t\t\t\t%s /* %s */," % (ids["target"], PRODUCT))
    add("\t\t\t);")
    add("\t\t};")
    add("/* End PBXProject section */")
    add("")

    # PBXResourcesBuildPhase
    add("/* Begin PBXResourcesBuildPhase section */")
    add("\t\t%s /* Resources */ = {" % ids["resources_phase"])
    add("\t\t\tisa = PBXResourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for name, _, build_file in resource_entries:
        add("\t\t\t\t%s /* %s in Resources */," % (build_file, name))
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXResourcesBuildPhase section */")
    add("")

    # PBXSourcesBuildPhase
    add("/* Begin PBXSourcesBuildPhase section */")
    add("\t\t%s /* Sources */ = {" % ids["sources_phase"])
    add("\t\t\tisa = PBXSourcesBuildPhase;")
    add("\t\t\tbuildActionMask = 2147483647;")
    add("\t\t\tfiles = (")
    for group, name, _, build_file in source_entries:
        add("\t\t\t\t%s /* %s in Sources */," % (build_file, name))
    add("\t\t\t);")
    add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    add("\t\t};")
    add("/* End PBXSourcesBuildPhase section */")
    add("")

    project_common = [
        "ALWAYS_SEARCH_USER_PATHS = NO;",
        "CLANG_ENABLE_MODULES = YES;",
        "CLANG_ENABLE_OBJC_ARC = YES;",
        "CODE_SIGNING_ALLOWED = NO;",
        "CODE_SIGNING_REQUIRED = NO;",
        "COPY_PHASE_STRIP = NO;",
        "ENABLE_STRICT_OBJC_MSGSEND = YES;",
        "GCC_C_LANGUAGE_STANDARD = gnu11;",
        "GCC_NO_COMMON_BLOCKS = YES;",
        "MACOSX_DEPLOYMENT_TARGET = 13.0;",
        "SDKROOT = macosx;",
        "SWIFT_VERSION = 5.0;",
    ]

    target_common = [
        "CODE_SIGNING_ALLOWED = NO;",
        "CODE_SIGNING_REQUIRED = NO;",
        "COMBINE_HIDPI_IMAGES = YES;",
        "CURRENT_PROJECT_VERSION = 7;",
        "ENABLE_HARDENED_RUNTIME = NO;",
        "GENERATE_INFOPLIST_FILE = NO;",
        "INFOPLIST_FILE = AnyPaste/Info.plist;",
        "LD_RUNPATH_SEARCH_PATHS = (",
        "\t\t\t\t\t\"$(inherited)\",",
        "\t\t\t\t\t\"@executable_path/../Frameworks\",",
        "\t\t\t\t);",
        "MARKETING_VERSION = 1.0.6;",
        "PRODUCT_BUNDLE_IDENTIFIER = %s;" % BUNDLE_ID,
        "PRODUCT_NAME = %s;" % PRODUCT,
        "SWIFT_EMIT_LOC_STRINGS = NO;",
        "SWIFT_VERSION = 5.0;",
    ]

    add("/* Begin XCBuildConfiguration section */")

    def emit_config(config_id, name, settings, extra_header):
        add("\t\t%s /* %s */ = {" % (config_id, extra_header))
        add("\t\t\tisa = XCBuildConfiguration;")
        add("\t\t\tbuildSettings = {")
        for entry in settings:
            add("\t\t\t\t" + entry)
        add("\t\t\t};")
        add("\t\t\tname = %s;" % name)
        add("\t\t};")

    emit_config(
        ids["project_debug"],
        "Debug",
        project_common + [
            "DEBUG_INFORMATION_FORMAT = dwarf;",
            "ENABLE_TESTABILITY = YES;",
            "GCC_OPTIMIZATION_LEVEL = 0;",
            "GCC_PREPROCESSOR_DEFINITIONS = (",
            "\t\t\t\t\t\"DEBUG=1\",",
            "\t\t\t\t\t\"$(inherited)\",",
            "\t\t\t\t);",
            "ONLY_ACTIVE_ARCH = YES;",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;",
            "SWIFT_OPTIMIZATION_LEVEL = \"-Onone\";",
        ],
        "Debug",
    )
    emit_config(
        ids["project_release"],
        "Release",
        project_common + [
            "ARCHS = (",
            "\t\t\t\t\tarm64,",
            "\t\t\t\t\tx86_64,",
            "\t\t\t\t);",
            "DEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";",
            "ENABLE_NS_ASSERTIONS = NO;",
            "ONLY_ACTIVE_ARCH = NO;",
            "SWIFT_COMPILATION_MODE = wholemodule;",
            "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
        ],
        "Release",
    )
    emit_config(ids["target_debug"], "Debug", target_common, "Debug")
    emit_config(ids["target_release"], "Release", target_common, "Release")

    add("/* End XCBuildConfiguration section */")
    add("")

    add("/* Begin XCConfigurationList section */")
    add("\t\t%s /* Build configuration list for PBXProject \"%s\" */ = {" % (ids["project_config_list"], PRODUCT))
    add("\t\t\tisa = XCConfigurationList;")
    add("\t\t\tbuildConfigurations = (")
    add("\t\t\t\t%s /* Debug */," % ids["project_debug"])
    add("\t\t\t\t%s /* Release */," % ids["project_release"])
    add("\t\t\t);")
    add("\t\t\tdefaultConfigurationIsVisible = 0;")
    add("\t\t\tdefaultConfigurationName = Release;")
    add("\t\t};")
    add("\t\t%s /* Build configuration list for PBXNativeTarget \"%s\" */ = {" % (ids["target_config_list"], PRODUCT))
    add("\t\t\tisa = XCConfigurationList;")
    add("\t\t\tbuildConfigurations = (")
    add("\t\t\t\t%s /* Debug */," % ids["target_debug"])
    add("\t\t\t\t%s /* Release */," % ids["target_release"])
    add("\t\t\t);")
    add("\t\t\tdefaultConfigurationIsVisible = 0;")
    add("\t\t\tdefaultConfigurationName = Release;")
    add("\t\t};")
    add("/* End XCConfigurationList section */")
    add("")
    add("\t};")
    add("\trootObject = %s /* Project object */;" % ids["project"])
    add("}")

    os.makedirs(PROJECT_DIR, exist_ok=True)
    with open(os.path.join(PROJECT_DIR, "project.pbxproj"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")

    scheme_dir = os.path.join(PROJECT_DIR, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{ids['target']}"
               BuildableName = "{PRODUCT}.app"
               BlueprintName = "{PRODUCT}"
               ReferencedContainer = "container:{PRODUCT}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ids['target']}"
            BuildableName = "{PRODUCT}.app"
            BlueprintName = "{PRODUCT}"
            ReferencedContainer = "container:{PRODUCT}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{ids['target']}"
            BuildableName = "{PRODUCT}.app"
            BlueprintName = "{PRODUCT}"
            ReferencedContainer = "container:{PRODUCT}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    with open(os.path.join(scheme_dir, f"{PRODUCT}.xcscheme"), "w", encoding="utf-8") as handle:
        handle.write(scheme)

    print("wrote", os.path.join(PROJECT_DIR, "project.pbxproj"))
    print("wrote", os.path.join(scheme_dir, f"{PRODUCT}.xcscheme"))


if __name__ == "__main__":
    main()
