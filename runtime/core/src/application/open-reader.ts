import type {
  OpenReaderInput,
  OpenReaderResult,
  ReaderPageEntry,
} from "../domain/reader.js";
import type { ChapterId } from "../domain/identifiers.js";
import type { Page, PageOrderWithItems } from "../domain/page.js";
import type { CoreUseCaseDependencies } from "../ports/use-case-dependencies.js";
import { isErr, ok, type Result } from "../shared/result.js";
import { fail, unexpectedFailure } from "./helpers.js";
import { ResolveReaderTarget } from "./resolve-reader-target.js";

export class OpenReader {
  private readonly resolveReaderTarget: ResolveReaderTarget;

  constructor(private readonly dependencies: CoreUseCaseDependencies) {
    this.resolveReaderTarget = new ResolveReaderTarget(dependencies);
  }

  async execute(input: OpenReaderInput): Promise<Result<OpenReaderResult>> {
    try {
      const target = await this.resolveReaderTarget.execute(input);
      if (isErr(target)) {
        return target;
      }

      const chapter = await this.dependencies.repositories.chapters.getById(target.value.chapterId);
      if (isErr(chapter)) {
        return chapter;
      }

      if (chapter.value === null) {
        return fail(
          "READER_UNRESOLVED_LOCAL_TARGET",
          "Resolved chapter no longer exists.",
        );
      }

      const pagesResult = await this.dependencies.repositories.pages.listByChapter(target.value.chapterId);
      if (isErr(pagesResult)) {
        return pagesResult;
      }

      const activeOrderResult = await this.dependencies.repositories.pageOrders.getActiveOrder(
        target.value.chapterId,
      );
      if (isErr(activeOrderResult)) {
        return activeOrderResult;
      }

      const orderedPagesResult = this.resolveOrderedPages(
        target.value.chapterId,
        pagesResult.value,
        activeOrderResult.value,
      );
      if (isErr(orderedPagesResult)) {
        return orderedPagesResult;
      }

      if (orderedPagesResult.value.pages.length === 0) {
        return fail("NOT_FOUND", "No pages exist for the resolved chapter.");
      }

      const resolvedPage = orderedPagesResult.value.pages.find(
        (entry) => entry.page.pageIndex === target.value.pageIndex,
      );
      if (resolvedPage === undefined) {
        return fail(
          "READER_INVALID_POSITION",
          "Reader page index does not map to a canonical page in the chapter.",
          {
            pageIndex: target.value.pageIndex,
            pageCount: orderedPagesResult.value.pages.length,
          },
        );
      }

      return ok({
        target: target.value,
        chapter: chapter.value,
        activeOrder: orderedPagesResult.value.activeOrder,
        pages: orderedPagesResult.value.pages,
      });
    } catch (cause) {
      return unexpectedFailure("OpenReader failed.", cause);
    }
  }

  private resolveOrderedPages(
    chapterId: ChapterId,
    pages: readonly Page[],
    activeOrder: PageOrderWithItems | null,
  ): Result<{ activeOrder: PageOrderWithItems; pages: readonly ReaderPageEntry[] }> {
    if (activeOrder === null) {
      const fallbackOrder = this.buildFallbackOrder(chapterId as never, pages);
      return ok({
        activeOrder: fallbackOrder,
        pages: fallbackOrder.items
          .map((item) => ({
            page: pages.find((page) => page.id === item.pageId)!,
            sortIndex: item.sortIndex,
          }))
          .sort((left, right) => left.sortIndex - right.sortIndex),
      });
    }

    const pagesById = new Map(pages.map((page) => [page.id, page]));
    if (activeOrder.order.pageCount !== pages.length || activeOrder.items.length !== pages.length) {
      return fail(
        "VALIDATION_ERROR",
        "Active page order must cover every page in the chapter exactly once.",
      );
    }

    const seenPageIds = new Set<string>();
    const seenSortIndexes = new Set<number>();
    const orderedPages: ReaderPageEntry[] = [];
    for (const item of activeOrder.items) {
      if (seenPageIds.has(item.pageId) || seenSortIndexes.has(item.sortIndex)) {
        return fail(
          "VALIDATION_ERROR",
          "Active page order contains duplicate page or sort positions.",
        );
      }

      seenPageIds.add(item.pageId);
      seenSortIndexes.add(item.sortIndex);

      const page = pagesById.get(item.pageId);
      if (page === undefined) {
        return fail(
          "VALIDATION_ERROR",
          "Active page order references a page outside the resolved chapter.",
        );
      }

      orderedPages.push({
        page,
        sortIndex: item.sortIndex,
      });
    }

    return ok({
      activeOrder,
      pages: orderedPages.sort((left, right) => left.sortIndex - right.sortIndex),
    });
  }

  private buildFallbackOrder(
    chapterId: ChapterId,
    pages: readonly Page[],
  ): PageOrderWithItems {
    const now = this.dependencies.clock.now();
    const orderedPages = [...pages].sort((left, right) => left.pageIndex - right.pageIndex);

    return {
      order: {
        id: `synthetic:${chapterId}` as never,
        chapterId: chapterId as never,
        orderKey: "source",
        orderType: "source",
        isActive: true,
        pageCount: orderedPages.length,
        createdAt: now,
        updatedAt: now,
      },
      items: orderedPages.map((page) => ({
        id: `synthetic:${page.id}` as never,
        pageOrderId: `synthetic:${chapterId}` as never,
        pageId: page.id,
        sortIndex: page.pageIndex,
        createdAt: page.createdAt,
      })),
    };
  }
}
