import { createHash } from "node:crypto";

import { createCoreError } from "../shared/errors.js";
import { err, ok, type Result } from "../shared/result.js";
import {
  validateProviderTagMapping,
  validateSourcePackageChecksums,
  validateSourcePackageManifest,
  validateSourceRepositoryPackageEntry,
  type ProviderTagMappingDocument,
  type SourcePackageManifest,
  type SourceRepositoryPackageEntry,
} from "./validators.js";

const SHA256_PATTERN = /^[0-9A-Fa-f]{64}$/;
const DEFAULT_SUPPORTED_RUNTIME_API_VERSIONS = ["v1"] as const;

export interface SourcePackageFile {
  readonly path: string;
  readonly bytes: Uint8Array;
}

export interface SourcePackageTaxonomyMapping {
  readonly path: string;
  readonly payload: unknown;
}

export interface SourcePackageIntegrityInput {
  readonly repositoryPackage: unknown;
  readonly manifest: unknown;
  readonly checksums: unknown;
  readonly files: readonly SourcePackageFile[];
  readonly archiveSha256: string;
  readonly taxonomyMappings?: readonly SourcePackageTaxonomyMapping[];
  readonly knownCanonicalKeys?: ReadonlySet<string>;
  readonly supportedRuntimeApiVersions?: readonly string[];
}

export interface VerifiedSourcePackage {
  readonly packageKey: string;
  readonly providerKey: string;
  readonly version: string;
  readonly manifest: SourcePackageManifest;
  readonly archiveSha256: string;
  readonly entrypointSha256: string;
  readonly entrypointPath: string;
  readonly taxonomyMappingPaths: readonly string[];
  readonly verifiedAt: string;
}

export interface SourcePackageIntegrityVerifier {
  verify(input: SourcePackageIntegrityInput): Result<VerifiedSourcePackage>;
}

export interface CreateSourcePackageIntegrityVerifierOptions {
  readonly now?: () => Date;
}

interface DuplicatePathIssue {
  readonly path: string;
  readonly indexes: readonly number[];
}

export function createSourcePackageIntegrityVerifier(
  options: CreateSourcePackageIntegrityVerifierOptions = {},
): SourcePackageIntegrityVerifier {
  const now = options.now ?? (() => new Date());

  return {
    verify(input: SourcePackageIntegrityInput): Result<VerifiedSourcePackage> {
      const repositoryPackageResult = validateSourceRepositoryPackageEntry(input.repositoryPackage);
      if (!repositoryPackageResult.ok) {
        return err(repositoryPackageResult.error);
      }

      const manifestResult = validateSourcePackageManifest(input.manifest);
      if (!manifestResult.ok) {
        return err(manifestResult.error);
      }

      const checksumsResult = validateSourcePackageChecksums(input.checksums);
      if (!checksumsResult.ok) {
        const details = checksumsResult.error.details;
        return err(
          createCoreError({
            code: "SOURCE_PACKAGE_CHECKSUM_MISMATCH",
            message: "Invalid source package checksums.",
            ...(details === undefined ? {} : { details }),
            cause: checksumsResult.error,
          }),
        );
      }

      const archiveSha256Result = normalizeSha256Input(input.archiveSha256);
      if (!archiveSha256Result.ok) {
        return err(
          createCoreError({
            code: "SOURCE_PACKAGE_HASH_MISMATCH",
            message: "Invalid archive SHA-256.",
            details: {
              field: "archiveSha256",
              value: input.archiveSha256,
              reason: "Expected a SHA-256 hex string.",
            },
          }),
        );
      }

      const repositoryPackage = repositoryPackageResult.value;
      const manifest = manifestResult.value;
      const checksums = checksumsResult.value;
      const archiveSha256 = archiveSha256Result.value;

      const duplicateFilePaths = findDuplicatePaths(input.files.map((file) => file.path));
      if (duplicateFilePaths.length > 0) {
        return err(
          createCoreError({
            code: "SOURCE_PACKAGE_CHECKSUM_MISMATCH",
            message: "Duplicate file paths are not allowed.",
            details: {
              duplicates: duplicateFilePaths.map((duplicate) => ({
                path: duplicate.path,
                indexes: [...duplicate.indexes],
              })),
            },
          }),
        );
      }

      const duplicateTaxonomyMappingPaths = findDuplicatePaths(
        (input.taxonomyMappings ?? []).map((mapping) => mapping.path),
      );
      if (duplicateTaxonomyMappingPaths.length > 0) {
        return err(
          createCoreError({
            code: "SOURCE_PACKAGE_TAXONOMY_INVALID",
            message: "Duplicate taxonomy mapping paths are not allowed.",
            details: {
              duplicates: duplicateTaxonomyMappingPaths.map((duplicate) => ({
                path: duplicate.path,
                indexes: [...duplicate.indexes],
              })),
            },
          }),
        );
      }

      if (repositoryPackage.sha256 !== archiveSha256) {
        return hashMismatchError("repositoryPackage.sha256", repositoryPackage.sha256, archiveSha256);
      }

      if (manifest.integrity.archiveSha256 !== archiveSha256) {
        return hashMismatchError(
          "manifest.integrity.archiveSha256",
          manifest.integrity.archiveSha256,
          archiveSha256,
        );
      }

      if (checksums.packageSha256 !== archiveSha256) {
        return hashMismatchError("checksums.packageSha256", checksums.packageSha256, archiveSha256);
      }

      const identityMismatch = findIdentityMismatch(repositoryPackage, manifest);
      if (identityMismatch !== null) {
        return err(
          createCoreError({
            code: "SOURCE_PACKAGE_IDENTITY_MISMATCH",
            message: "Source package identity mismatch.",
            details: identityMismatch,
          }),
        );
      }

      const supportedApiVersions = input.supportedRuntimeApiVersions
        ?? DEFAULT_SUPPORTED_RUNTIME_API_VERSIONS;
      if (!supportedApiVersions.includes(manifest.runtime.apiVersion)) {
        return err(
          createCoreError({
            code: "SOURCE_PACKAGE_API_UNSUPPORTED",
            message: "Unsupported runtime apiVersion.",
            details: {
              field: "manifest.runtime.apiVersion",
              value: manifest.runtime.apiVersion,
              supportedRuntimeApiVersions: [...supportedApiVersions],
            },
          }),
        );
      }

      const fileByPath = new Map<string, SourcePackageFile>();
      for (const file of input.files) {
        fileByPath.set(file.path, file);
      }

      const entrypointPath = manifest.runtime.entrypoint;
      const entrypointFile = fileByPath.get(entrypointPath);
      if (entrypointFile === undefined) {
        return err(
          createCoreError({
            code: "SOURCE_PACKAGE_ENTRYPOINT_MISSING",
            message: "Runtime entrypoint file is missing.",
            details: {
              path: entrypointPath,
            },
          }),
        );
      }

      const entrypointHash = computeSha256(entrypointFile.bytes);
      if (entrypointHash !== manifest.integrity.entrypointSha256) {
        return err(
          createCoreError({
            code: "SOURCE_PACKAGE_CHECKSUM_MISMATCH",
            message: "Runtime entrypoint checksum mismatch.",
            details: {
              path: entrypointPath,
              expected: manifest.integrity.entrypointSha256,
              actual: entrypointHash,
              field: "manifest.integrity.entrypointSha256",
            },
          }),
        );
      }

      for (const checksumFile of checksums.files) {
        const file = fileByPath.get(checksumFile.path);
        if (file === undefined) {
          return err(
            createCoreError({
              code: "SOURCE_PACKAGE_CHECKSUM_MISMATCH",
              message: "Checksummed file is missing from provided files.",
              details: {
                path: checksumFile.path,
              },
            }),
          );
        }

        const actualHash = computeSha256(file.bytes);
        if (actualHash !== checksumFile.sha256) {
          return err(
            createCoreError({
              code: "SOURCE_PACKAGE_CHECKSUM_MISMATCH",
              message: "Checksummed file hash mismatch.",
              details: {
                path: checksumFile.path,
                expected: checksumFile.sha256,
                actual: actualHash,
              },
            }),
          );
        }
      }

      const checksumPaths = new Set(checksums.files.map((entry) => entry.path));
      const taxonomyMappings = input.taxonomyMappings ?? [];
      const taxonomyMappingByPath = new Map<string, SourcePackageTaxonomyMapping>();
      for (const mapping of taxonomyMappings) {
        taxonomyMappingByPath.set(mapping.path, mapping);
      }

      const taxonomyMappingPaths = manifest.taxonomy?.mappingFiles ?? [];
      for (const taxonomyPath of taxonomyMappingPaths) {
        if (!fileByPath.has(taxonomyPath)) {
          return err(
            createCoreError({
              code: "SOURCE_PACKAGE_TAXONOMY_INVALID",
              message: "Taxonomy mapping file is missing from provided files.",
              details: {
                path: taxonomyPath,
              },
            }),
          );
        }

        if (!checksumPaths.has(taxonomyPath)) {
          return err(
            createCoreError({
              code: "SOURCE_PACKAGE_TAXONOMY_INVALID",
              message: "Taxonomy mapping file is missing from checksums.",
              details: {
                path: taxonomyPath,
              },
            }),
          );
        }

        if (!taxonomyMappingByPath.has(taxonomyPath)) {
          return err(
            createCoreError({
              code: "SOURCE_PACKAGE_TAXONOMY_INVALID",
              message: "Taxonomy mapping payload is missing.",
              details: {
                path: taxonomyPath,
              },
            }),
          );
        }
      }

      for (const mapping of taxonomyMappings) {
        const mappingResult = validateProviderTagMapping(
          mapping.payload,
          input.knownCanonicalKeys === undefined
            ? undefined
            : { knownCanonicalKeys: input.knownCanonicalKeys },
        );
        if (!mappingResult.ok) {
          return err(mappingResult.error);
        }

        const providerMismatch = validateMappingProviderKey(
          mapping.path,
          mappingResult.value,
          manifest.providerKey,
        );
        if (providerMismatch !== null) {
          return err(providerMismatch);
        }
      }

      return ok({
        packageKey: manifest.packageKey,
        providerKey: manifest.providerKey,
        version: manifest.version,
        manifest,
        archiveSha256,
        entrypointSha256: manifest.integrity.entrypointSha256,
        entrypointPath,
        taxonomyMappingPaths: [...taxonomyMappingPaths],
        verifiedAt: now().toISOString(),
      });
    },
  };
}

function computeSha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function normalizeSha256Input(payload: string): Result<string> {
  const trimmed = payload.trim();
  if (!SHA256_PATTERN.test(trimmed)) {
    return err(
      createCoreError({
        code: "SOURCE_PACKAGE_HASH_MISMATCH",
        message: "Invalid archive SHA-256.",
        details: {
          field: "archiveSha256",
          value: payload,
          reason: "Expected a SHA-256 hex string.",
        },
      }),
    );
  }

  return ok(trimmed.toLowerCase());
}

function hashMismatchError(field: string, expected: string, actual: string): Result<never> {
  return err(
    createCoreError({
      code: "SOURCE_PACKAGE_HASH_MISMATCH",
      message: "Archive SHA-256 mismatch.",
      details: {
        field,
        expected,
        actual,
      },
    }),
  );
}

function findIdentityMismatch(
  repositoryPackage: SourceRepositoryPackageEntry,
  manifest: SourcePackageManifest,
): { field: string; expected: string; actual: string } | null {
  const comparisons: Array<{ field: string; expected: string; actual: string }> = [
    {
      field: "packageKey",
      expected: repositoryPackage.packageKey,
      actual: manifest.packageKey,
    },
    {
      field: "providerKey",
      expected: repositoryPackage.providerKey,
      actual: manifest.providerKey,
    },
    {
      field: "version",
      expected: repositoryPackage.version,
      actual: manifest.version,
    },
  ];

  for (const comparison of comparisons) {
    if (comparison.expected !== comparison.actual) {
      return comparison;
    }
  }

  return null;
}

function validateMappingProviderKey(
  path: string,
  mapping: ProviderTagMappingDocument,
  expectedProviderKey: string,
) {
  if (mapping.providerKey === expectedProviderKey) {
    return null;
  }

  return createCoreError({
    code: "SOURCE_PACKAGE_TAXONOMY_INVALID",
    message: "Taxonomy mapping providerKey mismatch.",
    details: {
      path,
      expectedProviderKey,
      actualProviderKey: mapping.providerKey,
    },
  });
}

function findDuplicatePaths(paths: readonly string[]): readonly DuplicatePathIssue[] {
  const indexByPath = new Map<string, number[]>();
  paths.forEach((path, index) => {
    const indexes = indexByPath.get(path);
    if (indexes === undefined) {
      indexByPath.set(path, [index]);
      return;
    }

    indexes.push(index);
  });

  return [...indexByPath.entries()]
    .filter(([, indexes]) => indexes.length > 1)
    .map(([path, indexes]) => ({
      path,
      indexes,
    }))
    .sort((left, right) => left.path.localeCompare(right.path));
}
