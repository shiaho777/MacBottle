#!/usr/bin/env swift
//
//  generate-recipe-index.swift
//  MacBottle
//
//  Walks WhiskyKit/Sources/WhiskyKit/Recipes/ and produces a manifest
//  (`_index.json`) enumerating every recipe with its git blob sha and a
//  SHA-256 digest of the raw bytes. The manifest is consumed by the
//  client at runtime (`RemoteRecipeSource`) to decide what needs
//  downloading and to verify the bytes it receives.
//
//  Usage:
//      swift scripts/generate-recipe-index.swift
//
//  Exits non-zero if any recipe fails to decode. CI uses this both to
//  regenerate the manifest and as a second line of schema validation.
//
//  This script intentionally has no dependencies outside Foundation and
//  the shell `git` command so it runs on every GitHub Actions macOS and
//  Linux image without setup.
//

import Foundation

// MARK: - Domain types (mirrored from RemoteRecipeSource.swift minimally)

struct IndexEntry: Codable {
    let id: String
    let path: String
    let sha: String
    let size: Int
    let sha256: String
}

struct Manifest: Codable {
    let schema: Int
    let generatedAt: String
    let recipes: [IndexEntry]

    enum CodingKeys: String, CodingKey {
        case schema
        case generatedAt = "generated_at"
        case recipes
    }
}

// Minimal recipe decoder — we only need `id` out of each file for the
// manifest, so keeping this local avoids pulling in the full WhiskyKit
// module just to run the script.
struct RecipeID: Decodable {
    let id: String
}

// MARK: - Helpers

func shell(_ command: String, arguments: [String]) throws -> String {
    let process = Process()
    process.launchPath = "/usr/bin/env"
    process.arguments = [command] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "generate-recipe-index", code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: "\(command) \(arguments.joined(separator: " ")) failed"]
        )
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Git blob sha of a tracked file. Uses `git hash-object` which matches
/// the sha stored in GitHub's API without requiring a commit to exist.
func gitBlobSHA(of file: String) throws -> String {
    return try shell("git", arguments: ["hash-object", file])
}

/// SHA-256 hex digest of the raw file bytes. The runtime client
/// (`RemoteRecipeSource`) verifies downloads against this value, so it
/// must hash exactly the bytes on disk. macOS ships `shasum`, Linux
/// images ship `sha256sum`; both print `"<hex>  <filename>"`.
func sha256Hex(of file: String) throws -> String {
    if let digest = try? shell("shasum", arguments: ["-a", "256", file]) {
        return String(digest.split(separator: " ").first ?? "")
    }
    let digest = try shell("sha256sum", arguments: [file])
    guard let hex = digest.split(separator: " ").first else {
        throw NSError(
            domain: "generate-recipe-index", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "unrecognized sha256sum output for \(file)"]
        )
    }
    return String(hex)
}

// MARK: - Main

let fileManager = FileManager.default
let repoRoot = fileManager.currentDirectoryPath
let recipesRoot = "WhiskyKit/Sources/WhiskyKit/Recipes"
let absoluteRecipesRoot = repoRoot + "/" + recipesRoot
let outputPath = absoluteRecipesRoot + "/_index.json"

guard fileManager.fileExists(atPath: absoluteRecipesRoot) else {
    FileHandle.standardError.write(Data("Recipes directory not found at \(absoluteRecipesRoot)\n".utf8))
    exit(2)
}

guard let enumerator = fileManager.enumerator(atPath: absoluteRecipesRoot) else {
    FileHandle.standardError.write(Data("Failed to enumerate \(absoluteRecipesRoot)\n".utf8))
    exit(2)
}

var entries: [IndexEntry] = []
var failures: [String] = []
let decoder = JSONDecoder()

while let relative = enumerator.nextObject() as? String {
    // Skip the manifest itself and anything that isn't a recipe file.
    guard relative.hasSuffix(".json"), !relative.hasSuffix("_index.json") else { continue }

    let absolute = absoluteRecipesRoot + "/" + relative
    let repoRelative = recipesRoot + "/" + relative

    guard let data = fileManager.contents(atPath: absolute) else {
        failures.append("\(relative): could not read file")
        continue
    }

    let recipeID: RecipeID
    do {
        recipeID = try decoder.decode(RecipeID.self, from: data)
    } catch {
        failures.append("\(relative): \(error.localizedDescription)")
        continue
    }

    let sha: String
    do {
        sha = try gitBlobSHA(of: repoRelative)
    } catch {
        failures.append("\(relative): git hash-object failed")
        continue
    }

    let sha256: String
    do {
        sha256 = try sha256Hex(of: repoRelative)
    } catch {
        failures.append("\(relative): sha256 failed")
        continue
    }

    let size = (try? fileManager.attributesOfItem(atPath: absolute)[.size] as? Int) ?? data.count

    entries.append(IndexEntry(id: recipeID.id, path: relative, sha: sha, size: size, sha256: sha256))
}

if !failures.isEmpty {
    FileHandle.standardError.write(Data("Aborting: \(failures.count) recipe(s) failed validation:\n".utf8))
    for failure in failures {
        FileHandle.standardError.write(Data("  - \(failure)\n".utf8))
    }
    exit(1)
}

entries.sort { $0.id < $1.id }

let formatter = ISO8601DateFormatter()
formatter.formatOptions = [.withInternetDateTime]
let manifest = Manifest(
    schema: 1,
    generatedAt: formatter.string(from: Date()),
    recipes: entries
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let output = try encoder.encode(manifest)
try output.write(to: URL(fileURLWithPath: outputPath))

print("wrote \(entries.count) recipes to \(recipesRoot)/_index.json")
