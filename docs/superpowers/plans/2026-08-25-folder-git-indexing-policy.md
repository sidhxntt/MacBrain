# Folder and Git Indexing Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Index supported hidden and secret files for explicitly selected Folder and Git sources, while excluding only dependency and build directories.

**Architecture:** Keep recursive filtering in `LocalFileIndexer`, shared by Folder and Git connectors. Git remains constrained to tracked files through its existing allow-list; the shared indexer decides which tracked paths are readable and indexes hidden/secret files when supported.

**Tech Stack:** Swift 6, SwiftPM, Foundation, PDFKit, XCTest.

---

### Task 1: Verify selected-file policy

**Files:**
- Modify: `Tests/MacBrainTests/SourceConnectorTests.swift:7-30`
- Modify: `Sources/MacBrain/Services/LocalFileIndexer.swift:12-75`

- [x] **Step 1: Write failing Folder connector test**

```swift
func testFolderIndexesHiddenAndSecretFilesWhileSkippingDependencyAndBuildDirectories() async throws {
    // Create .env, .hidden/config.json, credentials.json, node_modules/package.txt, and dist/output.txt.
    // Assert first three supported files are indexed and the dependency/build files are absent.
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `env CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/macbrain-swiftpm-cache swift test --disable-sandbox --filter SourceConnectorTests/testFolderIndexesHiddenAndSecretFilesWhileSkippingDependencyAndBuildDirectories`

Expected: failure because `.env`, hidden files, and credential files are skipped.

- [x] **Step 3: Remove hidden/secret filtering while keeping dependency/build filtering**

```swift
private static let excludedDirectoryNames: Set<String> = [
    "node_modules", "build", ".build", "deriveddata", "dist", "vendor", "pods", ".swiftpm"
]

// Enumerate without .skipsHiddenFiles. Exclude descendants only when path contains an excluded directory name.
```

- [x] **Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: PASS.

### Task 2: Document selection policy in connector UI

**Files:**
- Modify: `Sources/MacBrain/Models/SourceConnector.swift:75-76`
- Modify: `docs/superpowers/specs/2026-08-25-folder-and-git-connectors-design.md`

- [x] **Step 1: Update Folder and Git connector copy**

```swift
case .folder: "Indexes supported files recursively, including hidden and secret files. Dependency and build folders are excluded."
case .gitRepository: "Indexes tracked supported files recursively, including hidden and secret files, plus local Git branches, commits, and changed-file metadata. Dependency and build folders are excluded."
```

- [x] **Step 2: Update design behavior text**

Replace the old hidden/credential exclusion statement with the same explicit inclusion/exclusion policy.

- [x] **Step 3: Run full verification and package without launch**

Run:

```bash
env CLANG_MODULE_CACHE_PATH=/tmp/macbrain-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/macbrain-swiftpm-cache swift test --disable-sandbox
bash script/build_and_run.sh --bundle
```

Expected: all tests pass and `dist/MacBrain.app` is rebuilt without launching.
