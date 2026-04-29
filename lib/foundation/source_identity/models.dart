const String sourceIdentitySchemaVersion = 'source_identity/v1';

const String localSourceKey = 'local';
const String remoteSourceRefTypeKey = 'remote';
const String localSourceRefTypeKey = 'local';
const String unknownSourceKeyPrefix = 'Unknown:';

const String localSourceKind = 'local';
const String remoteSourceKind = 'remote';
const String unknownSourceKind = 'unknown';
const String webdavSourceKind = 'webdav';
const String otherSourceKind = 'other';

const Map<int, String> legacySourceTypeSourceKeys = <int, String>{
  0: 'picacg',
  1: 'ehentai',
  2: 'jm',
  3: 'hitomi',
  4: 'wnacg',
  5: 'nhentai',
  6: 'nhentai',
};

class SourceIdentityAudit {
  final String? source;
  final String? loadedFrom;
  final String? declaredVersion;
  final Map<String, Object?> metadata;

  const SourceIdentityAudit({
    this.source,
    this.loadedFrom,
    this.declaredVersion,
    this.metadata = const <String, Object?>{},
  });

  Map<String, dynamic> toJson() {
    return {
      'source': source,
      'loadedFrom': loadedFrom,
      'declaredVersion': declaredVersion,
      'metadata': metadata,
    };
  }

  factory SourceIdentityAudit.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    return SourceIdentityAudit(
      source: json['source'] as String?,
      loadedFrom: json['loadedFrom'] as String?,
      declaredVersion: json['declaredVersion'] as String?,
      metadata: metadata is Map<String, dynamic>
          ? Map<String, Object?>.from(metadata)
          : const <String, Object?>{},
    );
  }
}

class SourceIdentity {
  final String schema;
  final String id;
  final String kind;
  final String key;
  final List<String> aliases;
  final List<String> names;
  final String? version;
  final SourceIdentityAudit? audit;

  const SourceIdentity({
    required this.schema,
    required this.id,
    required this.kind,
    required this.key,
    required this.aliases,
    required this.names,
    required this.version,
    required this.audit,
  });

  factory SourceIdentity.legacy({
    required String key,
    String? id,
    String? kind,
    Iterable<String> aliases = const <String>[],
    Iterable<String> names = const <String>[],
    String? version,
    SourceIdentityAudit? audit,
  }) {
    final resolvedKind = kind ?? sourceKindFromKey(key);
    final resolvedId = id ?? key;
    return SourceIdentity(
      schema: sourceIdentitySchemaVersion,
      id: resolvedId,
      kind: resolvedKind,
      key: key,
      aliases: _dedupeStrings(aliases),
      names: _dedupeStrings(names),
      version: version,
      audit: audit,
    );
  }

  factory SourceIdentity.fromJson(Map<String, dynamic> json) {
    final aliases = json['aliases'];
    final names = json['names'];
    final audit = json['audit'];
    return SourceIdentity(
      schema: (json['schema'] as String?) ?? sourceIdentitySchemaVersion,
      id: json['id'] as String,
      kind: (json['kind'] as String?) ?? remoteSourceKind,
      key: json['key'] as String,
      aliases: aliases is List
          ? _dedupeStrings(aliases.whereType<String>())
          : const <String>[],
      names: names is List
          ? _dedupeStrings(names.whereType<String>())
          : const <String>[],
      version: json['version'] as String?,
      audit: audit is Map<String, dynamic>
          ? SourceIdentityAudit.fromJson(audit)
          : null,
    );
  }

  int get typeValue => sourceTypeValueFromStableId(id, kind: kind);

  List<String> get knownKeys => _dedupeStrings(<String>[
    key,
    id,
    ...aliases,
  ].map(normalizeLegacyImportedSourceKey));

  bool matchesKey(String candidate) {
    final normalized = normalizeLegacyImportedSourceKey(candidate);
    return knownKeys.contains(normalized);
  }

  Map<String, dynamic> toJson() {
    return {
      'schema': schema,
      'id': id,
      'kind': kind,
      'key': key,
      'aliases': aliases,
      'names': names,
      'version': version,
      'audit': audit?.toJson(),
    };
  }
}

List<String> _dedupeStrings(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty || !seen.add(value)) {
      continue;
    }
    result.add(value);
  }
  return result;
}

String sourceKindFromKey(String key) {
  if (isLocalSourceKey(key)) {
    return localSourceKind;
  }
  if (isUnknownSourceKey(key)) {
    return unknownSourceKind;
  }
  return remoteSourceKind;
}

int stableSourceKeyId(String key) {
  if (isLocalSourceKey(key)) {
    return 0;
  }
  var hash = 0x811c9dc5;
  for (final byte in key.codeUnits) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

int sourceTypeValueFromStableId(String stableId, {String kind = remoteSourceKind}) {
  if (kind == localSourceKind || isLocalSourceKey(stableId)) {
    return 0;
  }
  final unknownTypeValue = parseUnknownSourceTypeValue(stableId);
  if (unknownTypeValue != null) {
    return unknownTypeValue;
  }
  return stableSourceKeyId(stableId);
}

int sourceTypeValueFromKey(String key) {
  return sourceTypeValueFromStableId(key, kind: sourceKindFromKey(key));
}

String sourceKeyFromTypeValue(int typeValue) {
  if (typeValue == 0) {
    return localSourceKey;
  }
  return '$unknownSourceKeyPrefix$typeValue';
}

SourceIdentity sourceIdentityFromKey(
  String key, {
  Iterable<String> aliases = const <String>[],
  Iterable<String> names = const <String>[],
  String? version,
  SourceIdentityAudit? audit,
}) {
  return SourceIdentity.legacy(
    key: key,
    aliases: aliases,
    names: names,
    version: version,
    audit: audit,
  );
}

bool isLocalSourceKey(String key) => key == localSourceKey;

bool isUnknownSourceKey(String key) => key.startsWith(unknownSourceKeyPrefix);

int? parseUnknownSourceTypeValue(String key) {
  if (!isUnknownSourceKey(key)) {
    return null;
  }
  return int.tryParse(key.substring(unknownSourceKeyPrefix.length));
}

int normalizeFavoriteJsonTypeValue({
  required int typeValue,
  required String coverPath,
}) {
  if (typeValue == 0 && !coverPath.startsWith('http')) {
    return 0;
  }
  final sourceKey = legacySourceTypeSourceKeys[typeValue];
  if (sourceKey == null) {
    return typeValue;
  }
  return sourceTypeValueFromKey(sourceKey);
}

int normalizeLegacyHistoryTypeValue(int typeValue) {
  final sourceKey = legacySourceTypeSourceKeys[typeValue];
  if (sourceKey == null) {
    return typeValue;
  }
  return sourceTypeValueFromKey(sourceKey);
}

String normalizeLegacyImportedSourceKey(String sourceKey) {
  if (sourceKey.toLowerCase() == 'htmanga') {
    return 'wnacg';
  }
  return sourceKey;
}

bool matchesSourceTypeValue({
  required String sourceKey,
  required int typeValue,
}) {
  return sourceTypeValueFromKey(sourceKey) == typeValue ||
      sourceKey.hashCode == typeValue;
}

bool matchesSourceIdentityTypeValue({
  required SourceIdentity identity,
  required int typeValue,
}) {
  if (identity.typeValue == typeValue) {
    return true;
  }
  for (final key in identity.knownKeys) {
    if (key.hashCode == typeValue) {
      return true;
    }
  }
  return false;
}
