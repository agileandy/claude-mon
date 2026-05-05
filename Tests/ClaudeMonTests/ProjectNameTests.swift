import Foundation
@testable import ClaudeMonKit

@MainActor
func runProjectNameSuite(_ r: Runner) {
    // Closure-injected pathExists lets us test both branches deterministically.
    let alwaysExists: (String) -> Bool = { _ in true }
    let neverExists: (String) -> Bool = { _ in false }

    r.test("projectName_simplePath_reconstructsAndUsesLastSegment") {
        let result = ProjectName.decode(dirName: "-Users-andy-foo", pathExists: alwaysExists)
        try expectEqual(result.display, "foo")
        try expectEqual(result.path, "/Users/andy/foo")
    }

    r.test("projectName_dotPrefixedDir_decodesDoubleDashAsDot") {
        // "-Users-andy--claude" → "/Users/andy/.claude"
        let result = ProjectName.decode(dirName: "-Users-andy--claude", pathExists: alwaysExists)
        try expectEqual(result.path, "/Users/andy/.claude")
        try expectEqual(result.display, ".claude")
    }

    r.test("projectName_pathDoesNotExist_fallsBackToLastSegment") {
        // Real-world: a path with spaces or weird chars that the reconstruction can't
        // recover. Reconstruction fails the existence check; we surface the last
        // segment as a sensible display name.
        let result = ProjectName.decode(
            dirName: "-Applications-Foo-Bar-app-Contents-backend",
            pathExists: neverExists
        )
        try expectEqual(result.display, "backend")
        try expect(result.path == nil, "path should be nil when not verified")
    }

    r.test("projectName_noLeadingDash_treatedAsBareName") {
        let result = ProjectName.decode(dirName: "myproject", pathExists: neverExists)
        try expectEqual(result.display, "myproject")
        try expect(result.path == nil)
    }

    r.test("projectName_emptyString_returnsEmptyDisplay") {
        let result = ProjectName.decode(dirName: "", pathExists: neverExists)
        try expectEqual(result.display, "")
        try expect(result.path == nil)
    }

    r.test("projectName_realFilesystem_decodesUsersHomeProject") {
        // Live check: a path everyone has — /Users/<whoever> — so this is portable
        // across machines without fixture setup.
        let home = NSHomeDirectory()
        let parts = home.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return }                   // skip on weird envs
        // Build the munged form: leading "-" + parts joined by "-".
        let munged = "-" + parts.joined(separator: "-")
        let result = ProjectName.decode(dirName: munged)
        try expectEqual(result.display, parts.last!)
        try expect(result.path == home, "should reconstruct $HOME, got \(String(describing: result.path))")
    }

    r.test("projectName_fullDisplay_collapsesHomeToTilde") {
        let result = ProjectName.decode(
            dirName: "-Users-andy-Dev-Space-myproj",
            homeDir: "/Users/andy",
            pathExists: alwaysExists
        )
        try expectEqual(result.fullDisplay, "~/Dev/Space/myproj")
    }

    r.test("projectName_fullDisplay_keepsAbsolutePathOutsideHome") {
        let result = ProjectName.decode(
            dirName: "-Applications-Foo",
            homeDir: "/Users/andy",
            pathExists: alwaysExists
        )
        try expectEqual(result.fullDisplay, "/Applications/Foo")
    }

    r.test("projectName_fullDisplay_unverifiedMungedPathStillShown") {
        // When pathExists returns false, fullDisplay is best-effort: still show the
        // reconstructed path so the user has context, even if it's lossy.
        let result = ProjectName.decode(
            dirName: "-Users-andy-foo",
            homeDir: "/Users/andy",
            pathExists: neverExists
        )
        try expect(result.path == nil)
        try expectEqual(result.fullDisplay, "~/foo")
    }

    r.test("projectName_fullDisplay_bareNameFallsBackToDisplay") {
        let result = ProjectName.decode(dirName: "myproject", pathExists: neverExists)
        try expectEqual(result.fullDisplay, "myproject")
    }
}
