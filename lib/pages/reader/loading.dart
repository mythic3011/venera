part of 'reader.dart';

class ReaderWithLoading extends StatefulWidget {
  const ReaderWithLoading({
    super.key,
    required this.id,
    this.sourceRef,
    this.sourceKey,
    this.initialEp,
    this.initialPage,
  }) : assert(sourceRef != null || sourceKey != null);

  final String id;

  final SourceRef? sourceRef;

  final String? sourceKey;

  final int? initialEp;

  final int? initialPage;

  @override
  State<ReaderWithLoading> createState() => _ReaderWithLoadingState();
}

class _ReaderWithLoadingState
    extends LoadingState<ReaderWithLoading, ReaderProps> {
  SourceRef get _sourceRef =>
      widget.sourceRef ??
      SourceRef.fromLegacy(
        comicId: widget.id,
        sourceKey: widget.sourceKey!,
      );

  bool get _isLocalSourceRef => _sourceRef.type == SourceRefType.local;

  @override
  Widget buildContent(BuildContext context, ReaderProps data) {
    return Reader(
      type: data.type,
      cid: data.cid,
      name: data.name,
      chapters: data.chapters,
      history: data.history,
      initialChapter: widget.initialEp ?? data.history.ep,
      initialPage: widget.initialPage ?? data.history.page,
      initialChapterGroup: data.history.group,
      sourceRef: _sourceRef,
      author: data.author,
      tags: data.tags,
    );
  }

  @override
  Future<Res<ReaderProps>> loadData() async {
    final type = ComicType.fromKey(_sourceRef.sourceKey);
    final history = HistoryManager().find(
      widget.id,
      type,
    );

    if (_isLocalSourceRef) {
      final localComic = LocalManager().find(
        widget.id,
        type,
      );
      if (localComic == null) {
        return Res.error("LOCAL_ASSET_MISSING");
      }
      return Res(
        ReaderProps(
          type: type,
          cid: widget.id,
          name: localComic.title,
          chapters: localComic.chapters,
          history: history ??
              History.fromModel(
                model: localComic,
                ep: 0,
                page: 0,
              ),
          author: localComic.subtitle,
          tags: localComic.tags,
        ),
      );
    }

    final comicSource = ComicSource.find(_sourceRef.sourceKey);
    if (comicSource == null) {
      return Res.error("SOURCE_NOT_AVAILABLE:${_sourceRef.sourceKey}");
    }

    final comic = await comicSource.loadComicInfo!(widget.id);
    if (comic.error) {
      return Res.fromErrorRes(comic);
    }
    return Res(
      ReaderProps(
        type: type,
        cid: widget.id,
        name: comic.data.title,
        chapters: comic.data.chapters,
        history: history ??
            History.fromModel(
              model: comic.data,
              ep: 0,
              page: 0,
            ),
        author: comic.data.findAuthor() ?? "",
        tags: comic.data.plainTags,
      ),
    );
  }
}

class ReaderProps {
  final ComicType type;

  final String cid;

  final String name;

  final ComicChapters? chapters;

  final History history;

  final String author;

  final List<String> tags;

  const ReaderProps({
    required this.type,
    required this.cid,
    required this.name,
    required this.chapters,
    required this.history,
    required this.author,
    required this.tags,
  });
}
