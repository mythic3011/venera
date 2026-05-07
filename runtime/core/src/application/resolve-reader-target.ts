import {
  parseDiagnosticsEventId,
  type ChapterId,
  type PageId,
} from "../domain/identifiers.js";
import type {
  ReaderOpenTarget,
  ResolveReaderTargetInput,
} from "../domain/reader.js";
import type { CoreUseCaseDependencies } from "../ports/use-case-dependencies.js";
import { isErr, ok, type Result } from "../shared/result.js";
import { fail, unexpectedFailure, withOptional } from "./helpers.js";

type ResolutionReason =
  "requested_chapter"
  | "saved_session"
  | "first_canonical_chapter";
type ChapterSourceContext = {
  readonly sourceOrder?: number;
  readonly createdAt: Date;
  readonly id: string;
};
type ChapterCandidate = {
  readonly chapterId: ChapterId;
  readonly pageIndex: number;
  readonly pageId?: PageId;
  readonly reason: ResolutionReason;
};
type ChapterSourceLinkWithRuntimeContext = {
  readonly id: string;
  readonly linkStatus: string;
  readonly createdAt: Date;
  readonly sourceOrder?: number;
  readonly sourcePlatformStatus?: string;
  readonly sourceLinkStatus?: string;
};

function isNumberedChapter(chapterNumber: number | null | undefined): boolean {
  return chapterNumber !== undefined && chapterNumber !== null && Number.isFinite(chapterNumber);
}

function compareNullableNumber(left: number | undefined, right: number | undefined): number {
  if (left === undefined && right === undefined) {
    return 0;
  }

  if (left === undefined) {
    return 1;
  }

  if (right === undefined) {
    return -1;
  }

  return left - right;
}

function compareChapterSourceContext(left: ChapterSourceContext, right: ChapterSourceContext): number {
  const sourceOrderComparison = compareNullableNumber(left.sourceOrder, right.sourceOrder);
  if (sourceOrderComparison !== 0) {
    return sourceOrderComparison;
  }

  const createdAtComparison = left.createdAt.getTime() - right.createdAt.getTime();
  if (createdAtComparison !== 0) {
    return createdAtComparison;
  }

  return left.id.localeCompare(right.id);
}

export class ResolveReaderTarget {
  constructor(private readonly dependencies: CoreUseCaseDependencies) {}

  async execute(
    input: ResolveReaderTargetInput,
  ): Promise<Result<ReaderOpenTarget>> {
    try {
      const comic = await this.dependencies.repositories.comics.getById(input.comicId);
      if (isErr(comic)) {
        return comic;
      }

      if (comic.value === null) {
        return fail("NOT_FOUND", "Comic not found.");
      }

      const resolvedChapter = await this.resolveChapter(input);
      if (isErr(resolvedChapter)) {
        return resolvedChapter;
      }

      const sourceContext = await this.resolveSourceContext(resolvedChapter.value.chapterId);
      if (isErr(sourceContext)) {
        return sourceContext;
      }

      return ok(withOptional({
        comicId: input.comicId,
        chapterId: resolvedChapter.value.chapterId,
        pageIndex: resolvedChapter.value.pageIndex,
        sourceKind: sourceContext.value.sourceKind,
        resolutionReason: resolvedChapter.value.reason,
      }, "pageId", resolvedChapter.value.pageId));
    } catch (cause) {
      return unexpectedFailure("ResolveReaderTarget failed.", cause);
    }
  }

  private async resolveChapter(
    input: ResolveReaderTargetInput,
  ): Promise<Result<ChapterCandidate>> {
    if (input.chapterId !== undefined) {
      const chapter = await this.dependencies.repositories.chapters.getById(input.chapterId);
      if (isErr(chapter)) {
        return chapter;
      }

      if (chapter.value === null || chapter.value.comicId !== input.comicId) {
        return this.emitUnresolvedTarget(input, "requested_chapter_missing");
      }

      return ok({
        chapterId: chapter.value.id,
        pageIndex: input.pageIndex ?? 0,
        reason: "requested_chapter",
      });
    }

    const savedSession = await this.dependencies.repositories.readerSessions.getByComic(
      input.comicId,
    );
    if (isErr(savedSession)) {
      return savedSession;
    }

    if (savedSession.value !== null) {
      const validatedSavedSession = await this.resolveSavedSessionCandidate(
        input,
        savedSession.value.chapterId,
        savedSession.value.pageIndex,
        savedSession.value.pageId,
      );
      if (isErr(validatedSavedSession)) {
        return validatedSavedSession;
      }

      return ok(validatedSavedSession.value);
    }

    const chapters = await this.dependencies.repositories.chapters.listByComic(input.comicId);
    if (isErr(chapters)) {
      return chapters;
    }

    const chapterCandidates = await Promise.all(
      chapters.value.map(async (chapter) => {
        const activeSourceLinks = await this.listActiveChapterSourceContexts(chapter.id);
        if (isErr(activeSourceLinks)) {
          return activeSourceLinks;
        }

        const aggregatedSourceOrder = activeSourceLinks.value.reduce<number | undefined>(
          (current, entry) => {
            if (entry.sourceOrder === undefined) {
              return current;
            }

            if (current === undefined) {
              return entry.sourceOrder;
            }

            return Math.min(current, entry.sourceOrder);
          },
          undefined,
        );

        return ok({
          chapter,
          aggregatedSourceOrder,
        });
      }),
    );

    for (const candidate of chapterCandidates) {
      if (isErr(candidate)) {
        return candidate;
      }
    }

    const firstChapter = chapterCandidates
      .map((candidate) => {
        if (!candidate.ok) {
          throw new Error("Unreachable candidate error after prior narrowing.");
        }

        return candidate.value;
      })
      .sort((left, right) => {
        const leftNumbered = isNumberedChapter(left.chapter.chapterNumber);
        const rightNumbered = isNumberedChapter(right.chapter.chapterNumber);
        if (leftNumbered !== rightNumbered) {
          return leftNumbered ? -1 : 1;
        }

        const chapterNumberComparison = compareNullableNumber(
          leftNumbered ? (left.chapter.chapterNumber ?? undefined) : undefined,
          rightNumbered ? (right.chapter.chapterNumber ?? undefined) : undefined,
        );
        if (chapterNumberComparison !== 0) {
          return chapterNumberComparison;
        }

        const aggregatedSourceOrderComparison = compareNullableNumber(
          left.aggregatedSourceOrder,
          right.aggregatedSourceOrder,
        );
        if (aggregatedSourceOrderComparison !== 0) {
          return aggregatedSourceOrderComparison;
        }

        const createdAtComparison =
          left.chapter.createdAt.getTime() - right.chapter.createdAt.getTime();
        if (createdAtComparison !== 0) {
          return createdAtComparison;
        }

        return left.chapter.id.localeCompare(right.chapter.id);
      })[0];
    if (firstChapter === undefined) {
      return this.emitUnresolvedTarget(input, "missing_local_chapter_id");
    }

    return ok({
      chapterId: firstChapter.chapter.id,
      pageIndex: 0,
      reason: "first_canonical_chapter",
    });
  }

  private async resolveSourceContext(
    chapterId: ChapterId,
  ): Promise<Result<{
    sourceKind: "local" | "remote";
  }>> {
    const activeChapterSourceLinks = await this.listActiveChapterSourceContexts(chapterId);
    if (isErr(activeChapterSourceLinks)) {
      return activeChapterSourceLinks;
    }

    const activeLink = [...activeChapterSourceLinks.value].sort(compareChapterSourceContext)[0];
    if (activeLink === undefined) {
      return ok({
        sourceKind: "local",
      });
    }

    return ok({
      sourceKind: "remote",
    });
  }

  private async resolveSavedSessionCandidate(
    input: ResolveReaderTargetInput,
    chapterId: ChapterId,
    pageIndex: number,
    pageId: PageId | undefined,
  ): Promise<Result<ChapterCandidate>> {
    const chapter = await this.dependencies.repositories.chapters.getById(chapterId);
    if (isErr(chapter)) {
      return chapter;
    }

    if (chapter.value === null || chapter.value.comicId !== input.comicId) {
      return this.emitUnresolvedTarget(input, "saved_session_invalid_chapter");
    }

    const pages = await this.dependencies.repositories.pages.listByChapter(chapterId);
    if (isErr(pages)) {
      return pages;
    }

    const pageAtIndex = pages.value.find((page) => page.pageIndex === pageIndex);
    if (pageAtIndex === undefined) {
      return this.emitUnresolvedTarget(input, "saved_session_invalid_page_index");
    }

    if (pageId !== undefined) {
      const page = await this.dependencies.repositories.pages.getById(pageId);
      if (isErr(page)) {
        return page;
      }

      if (
        page.value === null
        || page.value.chapterId !== chapterId
        || page.value.pageIndex !== pageIndex
      ) {
        return this.emitUnresolvedTarget(input, "saved_session_page_mismatch");
      }
    }

    return ok(withOptional({
      chapterId,
      pageIndex,
      reason: "saved_session",
    }, "pageId", pageId));
  }

  private async listActiveChapterSourceContexts(
    chapterId: ChapterId,
  ): Promise<Result<readonly ChapterSourceContext[]>> {
    const chapterLinks = await this.dependencies.repositories.chapterSourceLinks.listByChapter(
      chapterId,
    );
    if (isErr(chapterLinks)) {
      return chapterLinks;
    }

    const activeLinks = chapterLinks.value
      .filter((link): link is typeof link & ChapterSourceLinkWithRuntimeContext => {
        const runtimeLink = link as typeof link & ChapterSourceLinkWithRuntimeContext;
        return (
          runtimeLink.linkStatus === "active"
          && runtimeLink.sourceLinkStatus === "active"
          && runtimeLink.sourcePlatformStatus === "active"
        );
      })
      .map((link) => withOptional({
        createdAt: link.createdAt,
        id: link.id,
      }, "sourceOrder", (link as ChapterSourceLinkWithRuntimeContext).sourceOrder));

    return ok(activeLinks);
  }

  private async emitUnresolvedTarget(
    input: ResolveReaderTargetInput,
    reason: string,
  ): Promise<Result<never>> {
    const eventId = parseDiagnosticsEventId(this.dependencies.idGenerator.create());
    if (!isErr(eventId)) {
      await this.dependencies.repositories.diagnosticsEvents.record(withOptional({
        id: eventId.value,
        timestamp: this.dependencies.clock.now(),
        level: "warn",
        channel: "reader.route",
        eventName: "reader.route.unresolved_target",
        boundary: "reader.open",
        action: "rejected",
        authority: "canonical_db",
        comicId: input.comicId,
        payload: {
          comicId: input.comicId,
          chapterId: input.chapterId ?? null,
          sourceKind: "local",
          reason,
          action: "rejected",
        },
      }, "correlationId", input.correlationId));
    }

    return fail(
      "READER_UNRESOLVED_LOCAL_TARGET",
      "Unable to resolve a canonical reader target.",
      {
        reason,
      },
    );
  }
}
