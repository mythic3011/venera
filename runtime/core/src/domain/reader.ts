import type { Chapter } from "./chapter.js";
import type {
  ChapterId,
  ComicId,
  PageId,
  ReaderSessionId,
} from "./identifiers.js";
import type { Page, PageOrderWithItems } from "./page.js";

export const READER_SOURCE_KINDS = [
  "local",
  "remote",
] as const;

export type ReaderSourceKind = (typeof READER_SOURCE_KINDS)[number];

export const READER_TARGET_RESOLUTION_REASONS = [
  "requested_chapter",
  "saved_session",
  "first_canonical_chapter",
] as const;

export type ReaderTargetResolutionReason =
  (typeof READER_TARGET_RESOLUTION_REASONS)[number];

export const READER_SESSION_PERSIST_STATUSES = [
  "written",
  "skipped_unchanged",
  "skipped_duplicate_in_flight",
] as const;

export type ReaderSessionPersistStatus =
  (typeof READER_SESSION_PERSIST_STATUSES)[number];

export interface ReaderSession {
  readonly id: ReaderSessionId;
  readonly comicId: ComicId;
  readonly chapterId: ChapterId;
  readonly pageId?: PageId;
  readonly pageIndex: number;
  readonly createdAt: Date;
  readonly updatedAt: Date;
}

export interface ReaderSessionPersistResult {
  readonly session: ReaderSession;
  readonly status: ReaderSessionPersistStatus;
}

export interface ResolveReaderTargetInput {
  readonly comicId: ComicId;
  readonly chapterId?: ChapterId;
  readonly pageIndex?: number;
  readonly entrypoint?: string;
  readonly correlationId?: string;
}

export interface ReaderOpenTarget {
  readonly comicId: ComicId;
  readonly chapterId: ChapterId;
  readonly pageIndex: number;
  readonly pageId?: PageId;
  readonly sourceKind: ReaderSourceKind;
  readonly resolutionReason: ReaderTargetResolutionReason;
}

export interface OpenReaderInput {
  readonly comicId: ComicId;
  readonly chapterId?: ChapterId;
  readonly pageIndex?: number;
  readonly entrypoint?: string;
  readonly correlationId?: string;
}

export interface ReaderPageEntry {
  readonly page: Page;
  readonly sortIndex: number;
}

export interface OpenReaderResult {
  readonly target: ReaderOpenTarget;
  readonly chapter: Chapter;
  readonly activeOrder: PageOrderWithItems;
  readonly pages: readonly ReaderPageEntry[];
}

export interface UpdateReaderPositionInput {
  readonly comicId: ComicId;
  readonly chapterId: ChapterId;
  readonly pageId?: PageId;
  readonly pageIndex: number;
}
