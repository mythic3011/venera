import { describe, expect, it } from "vitest";

import {
  collectModuleSpecifiers,
  listTypeScriptFiles,
  readCoreFile,
  relativeToCore,
  stripComments,
} from "../support/source-scan.js";

const historicalRuntimeSegment = ["lib", "lega", "cy"].join("/");
const oldFlagColumn = ["is", "enabled"].join("_");
const oldFlagProperty = ["is", "Enabled"].join("");
const oldCompatToken = ["com", "pat"].join("");

const forbiddenHistoricalPatterns = [
  /\.dart$/i,
  /package:flutter\b/i,
  new RegExp(`(?:^|\\/)${historicalRuntimeSegment}(?:\\/|$)`),
  /(?:^|\/)\.\.\/venera-core(?:\/|$)/,
  /(?:^|\/)\.\.\/\.\.\/venera-core(?:\/|$)/,
  /(?:^|\/)venera-core(?:\/|$)/,
];

const forbiddenDataAccessImports = [
  /^kysely(?:\/.*)?$/,
  /^better-sqlite3$/,
  /^node:sqlite(?:\/.*)?$/,
  /(?:^|\/)\.\.\/db(?:\/|$)/,
  /(?:^|\/)\.\.\/repositories(?:\/|$)/,
  new RegExp(`(?:^|\\/)\\.\\.\\/${["lega", "cy"].join("")}(?:\\/|$)`),
];

const forbiddenSourceContractsImports = [
  /^(?:node:)?fs(?:\/.*)?$/,
  /^(?:node:)?path(?:\/.*)?$/,
  /^(?:node:)?http(?:\/.*)?$/,
  /^(?:node:)?https(?:\/.*)?$/,
  /^kysely(?:\/.*)?$/,
  /^better-sqlite3$/,
  /(?:^|\/)\.\.\/db(?:\/|$)/,
  /(?:^|\/)\.\.\/repositories(?:\/|$)/,
  /(?:^|\/)\.\.\/runtime(?:\/|$)/,
  /(?:^|\/)\.\.\/sandbox(?:\/|$)/,
  /(?:^|\/)sandbox(?:\/|$)/,
];

const forbiddenSurfacePatterns = [
  new RegExp(`\\b${oldFlagColumn}\\b`),
  new RegExp(`\\b${oldFlagProperty}\\b`),
  new RegExp(`\\b${oldCompatToken}\\b`, "i"),
  /\bFavorite\b/,
  /\bfavorites?\b/,
];

function findForbiddenImports(relativeDir: string, patterns: readonly RegExp[]): string[] {
  return listTypeScriptFiles(relativeDir).flatMap((filePath) => {
    const sourceText = readCoreFile(relativeToCore(filePath));
    if (sourceText === null) {
      return [];
    }

    return collectModuleSpecifiers(sourceText)
      .filter((specifier) => patterns.some((pattern) => pattern.test(specifier)))
      .map((specifier) => `${relativeToCore(filePath)} -> ${specifier}`);
  });
}

function findForbiddenSurfaceTokens(relativeDir: string, patterns: readonly RegExp[]): string[] {
  return listTypeScriptFiles(relativeDir).flatMap((filePath) => {
    const sourceText = readCoreFile(relativeToCore(filePath));
    if (sourceText === null) {
      return [];
    }

    const stripped = stripComments(sourceText);
    return patterns
      .filter((pattern) => pattern.test(stripped))
      .map((pattern) => `${relativeToCore(filePath)} -> ${pattern.source}`);
  });
}

describe("runtime/core architectural boundaries", () => {
  it("does not depend on Flutter, Dart historical runtime, or ../venera-core from src", () => {
    const violations = findForbiddenImports("src", forbiddenHistoricalPatterns);
    expect(violations).toEqual([]);
  });

  it("keeps db adapters, schema wiring, and historical imports out of src/domain, src/application, and src/ports", () => {
    const violations = [
      ...findForbiddenImports("src/domain", forbiddenDataAccessImports),
      ...findForbiddenImports("src/application", forbiddenDataAccessImports),
      ...findForbiddenImports("src/ports", forbiddenDataAccessImports),
    ];

    expect(violations).toEqual([]);
  });

  it("keeps src/index.ts free of db, repository adapter, and schema internals when the entrypoint exists", () => {
    const indexSource = readCoreFile("src/index.ts");

    if (indexSource === null) {
      expect(indexSource).toBeNull();
      return;
    }

    const strippedSource = stripComments(indexSource);
    const moduleSpecifiers = collectModuleSpecifiers(strippedSource);

    const forbiddenReExports = moduleSpecifiers.filter(
      (specifier) =>
        specifier.startsWith("./db") ||
        specifier.startsWith("./repositories") ||
        specifier.includes("/sqlite") ||
        specifier.includes("/schema") ||
        specifier.includes("/rows") ||
        specifier.includes("/tables"),
    );

    const forbiddenPublicNames = [...strippedSource.matchAll(/\b([A-Za-z0-9_]+(?:Row|Rows|Table|Tables|Schema|Schemas))\b/g)].map(
      (match) => match[1],
    );

    expect(forbiddenReExports).toEqual([]);
    expect(forbiddenPublicNames).toEqual([]);
    expect(strippedSource).not.toMatch(/\bcreateCoreDatabase\b/);
    expect(strippedSource).not.toMatch(/\bKysely\b/);
  });

  it("keeps src/source-contracts pure from fs/network/db/repository/sandbox-runtime imports", () => {
    const violations = findForbiddenImports("src/source-contracts", forbiddenSourceContractsImports);
    expect(violations).toEqual([]);
  });

  it("has no active core surface for retired flag names or favorites", () => {
    const violations = findForbiddenSurfaceTokens("src", forbiddenSurfacePatterns);
    expect(violations).toEqual([]);
  });
});
