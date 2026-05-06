import { createHash } from "node:crypto";

import { describe, expect, it } from "vitest";

import {
  createSourcePackageIntegrityVerifier,
  type ProviderTagMappingDocument,
  type SourcePackageChecksums,
  type SourcePackageFile,
  type SourcePackageIntegrityInput,
  type SourcePackageManifest,
  type SourceRepositoryPackageEntry,
} from "../../src/index.js";

const UPPER_HASH = "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789";
const LOWER_HASH = UPPER_HASH.toLowerCase();
const FIXED_NOW = new Date("2026-05-06T10:00:00.000Z");
const textEncoder = new TextEncoder();

function hashText(content: string): string {
  return createHash("sha256").update(textEncoder.encode(content)).digest("hex");
}

function hashBytes(content: Uint8Array): string {
  return createHash("sha256").update(content).digest("hex");
}

function createBaseFiles(): SourcePackageFile[] {
  return [
    {
      path: "dist/index.js",
      bytes: textEncoder.encode("export const runtime = 'ok';"),
    },
    {
      path: "taxonomy/mapping.json",
      bytes: textEncoder.encode('{"schemaVersion":"1.0.0"}'),
    },
  ];
}

function createRepositoryPackageEntry(
  archiveSha256: string,
  overrides: Partial<SourceRepositoryPackageEntry> = {},
): SourceRepositoryPackageEntry {
  return {
    packageKey: "copymanga",
    providerKey: "copymanga",
    displayName: "CopyManga",
    version: "1.2.3",
    manifestUrl: "packages/copymanga/manifest.json",
    packageUrl: "packages/copymanga/package.zip",
    sha256: archiveSha256,
    minCoreVersion: "0.1.0",
    capabilities: ["search", "detail"],
    permissions: ["network.https"],
    ...overrides,
  };
}

function createManifest(
  archiveSha256: string,
  entrypointSha256: string,
  overrides: Partial<SourcePackageManifest> = {},
): SourcePackageManifest {
  return {
    schemaVersion: "1.0.0",
    packageKey: "copymanga",
    providerKey: "copymanga",
    displayName: "CopyManga",
    version: "1.2.3",
    runtime: {
      kind: "module",
      entrypoint: "dist/index.js",
      apiVersion: "v1",
    },
    capabilities: ["search", "detail"],
    permissions: ["network.https"],
    integrity: {
      archiveSha256,
      entrypointSha256,
    },
    taxonomy: {
      mappingFiles: ["taxonomy/mapping.json"],
    },
    ...overrides,
  };
}

function createChecksums(
  archiveSha256: string,
  files: readonly SourcePackageFile[],
  overrides: Partial<SourcePackageChecksums> = {},
): SourcePackageChecksums {
  return {
    files: files.map((file) => ({
      path: file.path,
      sha256: hashBytes(file.bytes),
    })),
    packageSha256: archiveSha256,
    ...overrides,
  };
}

function createMapping(
  overrides: Partial<ProviderTagMappingDocument> = {},
): ProviderTagMappingDocument {
  return {
    schemaVersion: "1.0.0",
    providerKey: "copymanga",
    sourceLocale: "zh-CN",
    mappings: [
      {
        remoteTagKey: "热血",
        remoteLabel: "热血",
        canonicalKey: "theme.action",
        confidence: "manual",
      },
    ],
    ...overrides,
  };
}

function createValidInput(overrides: Partial<SourcePackageIntegrityInput> = {}): SourcePackageIntegrityInput {
  const files = createBaseFiles();
  const archiveSha256 = LOWER_HASH;
  const entrypointSha256 = hashText("export const runtime = 'ok';");

  return {
    repositoryPackage: createRepositoryPackageEntry(archiveSha256),
    manifest: createManifest(archiveSha256, entrypointSha256),
    checksums: createChecksums(archiveSha256, files),
    files,
    archiveSha256,
    taxonomyMappings: [
      {
        path: "taxonomy/mapping.json",
        payload: createMapping(),
      },
    ],
    ...overrides,
  };
}

describe("createSourcePackageIntegrityVerifier", () => {
  it("valid package verifies successfully", () => {
    const verifier = createSourcePackageIntegrityVerifier({ now: () => FIXED_NOW });
    const valid = createValidInput();

    const result = verifier.verify(valid);

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.packageKey).toBe("copymanga");
      expect(result.value.providerKey).toBe("copymanga");
      expect(result.value.version).toBe("1.2.3");
      expect(result.value.entrypointPath).toBe("dist/index.js");
      expect(result.value.taxonomyMappingPaths).toEqual(["taxonomy/mapping.json"]);
      expect(result.value.verifiedAt).toBe(FIXED_NOW.toISOString());
    }
  });

  it("archive hash mismatch rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const result = verifier.verify({
      ...createValidInput(),
      archiveSha256: "f".repeat(64),
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_HASH_MISMATCH");
    }
  });

  it("manifest packageKey mismatch rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      manifest: createManifest(LOWER_HASH, hashText("export const runtime = 'ok';"), {
        packageKey: "other",
      }),
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_IDENTITY_MISMATCH");
    }
  });

  it("manifest providerKey mismatch rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      manifest: createManifest(LOWER_HASH, hashText("export const runtime = 'ok';"), {
        providerKey: "other",
      }),
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_IDENTITY_MISMATCH");
    }
  });

  it("manifest version mismatch rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      manifest: createManifest(LOWER_HASH, hashText("export const runtime = 'ok';"), {
        version: "2.0.0",
      }),
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_IDENTITY_MISMATCH");
    }
  });

  it("unsupported runtime apiVersion rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      manifest: createManifest(LOWER_HASH, hashText("export const runtime = 'ok';"), {
        runtime: {
          kind: "module",
          entrypoint: "dist/index.js",
          apiVersion: "v2",
        },
      }),
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_API_UNSUPPORTED");
    }
  });

  it("missing runtime entrypoint rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      files: valid.files.filter((file) => file.path !== "dist/index.js"),
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_ENTRYPOINT_MISSING");
    }
  });

  it("runtime entrypoint hash mismatch rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const tamperedFiles = valid.files.map((file) =>
      file.path === "dist/index.js"
        ? {
          ...file,
          bytes: textEncoder.encode("export const runtime = 'tampered';"),
        }
        : file,
    );

    const result = verifier.verify({
      ...valid,
      files: tamperedFiles,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_CHECKSUM_MISMATCH");
    }
  });

  it("missing checksummed file rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const checksums = createChecksums(LOWER_HASH, [
      ...valid.files,
      {
        path: "dist/extra.js",
        bytes: textEncoder.encode("extra"),
      },
    ]);

    const result = verifier.verify({
      ...valid,
      checksums,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_CHECKSUM_MISMATCH");
    }
  });

  it("checksummed file hash mismatch rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const checksums = createChecksums(LOWER_HASH, valid.files, {
      files: [
        {
          path: "dist/index.js",
          sha256: "f".repeat(64),
        },
        {
          path: "taxonomy/mapping.json",
          sha256: hashText('{"schemaVersion":"1.0.0"}'),
        },
      ],
    });

    const result = verifier.verify({
      ...valid,
      checksums,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_CHECKSUM_MISMATCH");
    }
  });

  it("taxonomy mapping path missing from files rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();
    const filesWithoutTaxonomy = valid.files.filter((file) => file.path !== "taxonomy/mapping.json");
    const checksumsWithoutTaxonomy = createChecksums(LOWER_HASH, filesWithoutTaxonomy);

    const result = verifier.verify({
      ...valid,
      files: filesWithoutTaxonomy,
      checksums: checksumsWithoutTaxonomy,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_TAXONOMY_INVALID");
    }
  });

  it("taxonomy mapping path missing from checksums rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const checksums = createChecksums(LOWER_HASH, valid.files, {
      files: [
        {
          path: "dist/index.js",
          sha256: hashText("export const runtime = 'ok';"),
        },
      ],
    });

    const result = verifier.verify({
      ...valid,
      checksums,
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_TAXONOMY_INVALID");
    }
  });

  it("missing taxonomyMappings payload rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      taxonomyMappings: [],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_TAXONOMY_INVALID");
    }
  });

  it("invalid taxonomy mapping payload rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      taxonomyMappings: [
        {
          path: "taxonomy/mapping.json",
          payload: {
            schemaVersion: "1.0.0",
            providerKey: "copymanga",
            sourceLocale: "zh-CN",
            mappings: [
              {
                remoteTagKey: "热血",
                remoteLabel: "热血",
                canonicalKey: "theme.action",
                confidence: "invalid",
              },
            ],
          },
        },
      ],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("TAG_MAPPING_INVALID");
    }
  });

  it("taxonomy mapping providerKey mismatch rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      taxonomyMappings: [
        {
          path: "taxonomy/mapping.json",
          payload: createMapping({ providerKey: "other-provider" }),
        },
      ],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_TAXONOMY_INVALID");
    }
  });

  it("unknown canonical key rejects when knownCanonicalKeys is supplied", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      taxonomyMappings: [
        {
          path: "taxonomy/mapping.json",
          payload: createMapping({
            mappings: [
              {
                remoteTagKey: "热血",
                remoteLabel: "热血",
                canonicalKey: "theme.unknown",
                confidence: "manual",
              },
            ],
          }),
        },
      ],
      knownCanonicalKeys: new Set(["theme.action"]),
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("TAG_MAPPING_INVALID");
    }
  });

  it("verified output contains no file bytes", () => {
    const verifier = createSourcePackageIntegrityVerifier({ now: () => FIXED_NOW });
    const result = verifier.verify(createValidInput());

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(Object.keys(result.value)).not.toContain("files");
      expect((result.value as unknown as { files?: unknown }).files).toBeUndefined();
    }
  });

  it("deterministic output with injected fixed now", () => {
    const verifier = createSourcePackageIntegrityVerifier({ now: () => FIXED_NOW });

    const result = verifier.verify(createValidInput());

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.verifiedAt).toBe("2026-05-06T10:00:00.000Z");
    }
  });

  it("uppercase hash inputs are normalized consistently", () => {
    const verifier = createSourcePackageIntegrityVerifier({ now: () => FIXED_NOW });
    const files = createBaseFiles();
    const entrypointSha256 = hashText("export const runtime = 'ok';");

    const result = verifier.verify({
      repositoryPackage: createRepositoryPackageEntry(LOWER_HASH),
      manifest: createManifest(UPPER_HASH, entrypointSha256),
      checksums: createChecksums(UPPER_HASH, files),
      files,
      archiveSha256: UPPER_HASH,
      taxonomyMappings: [
        {
          path: "taxonomy/mapping.json",
          payload: createMapping(),
        },
      ],
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.archiveSha256).toBe(LOWER_HASH);
      expect(result.value.entrypointSha256).toBe(entrypointSha256);
    }
  });

  it("duplicate files path rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      files: [
        ...valid.files,
        {
          path: "dist/index.js",
          bytes: textEncoder.encode("duplicate"),
        },
      ],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_CHECKSUM_MISMATCH");
    }
  });

  it("duplicate taxonomyMappings path rejects", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const valid = createValidInput();

    const result = verifier.verify({
      ...valid,
      taxonomyMappings: [
        {
          path: "taxonomy/mapping.json",
          payload: createMapping(),
        },
        {
          path: "taxonomy/mapping.json",
          payload: createMapping(),
        },
      ],
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_TAXONOMY_INVALID");
    }
  });

  it("archiveSha256 invalid shape rejects before comparison", () => {
    const verifier = createSourcePackageIntegrityVerifier();
    const result = verifier.verify({
      ...createValidInput(),
      archiveSha256: "invalid-hash",
    });

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.code).toBe("SOURCE_PACKAGE_HASH_MISMATCH");
    }
  });
});
