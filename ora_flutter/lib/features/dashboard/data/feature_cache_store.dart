import 'dart:convert';

import '../../activity/domain/final_activity.dart';
import '../domain/feature_models.dart';

abstract interface class FeatureCacheStore {
  Future<FeatureCacheSnapshot?> read(String ownerNik);
  Future<void> write(FeatureCacheSnapshot snapshot);
  Future<void> clear(String ownerNik);
}

abstract interface class FeatureCacheStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class FeatureCacheSnapshot {
  const FeatureCacheSnapshot({
    required this.ownerNik,
    required this.savedAtMillis,
    this.stats,
    this.quests,
    this.guildData,
    this.leaderboards = const {},
    this.activities,
  });

  static const schemaVersion = 1;
  final String ownerNik;
  final int savedAtMillis;
  final UserStats? stats;
  final List<Quest>? quests;
  final GuildData? guildData;
  final Map<String, LeaderboardData> leaderboards;
  final List<FinalActivity>? activities;

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'ownerNik': ownerNik,
    'savedAtMillis': savedAtMillis,
    'stats': stats?.toJson(),
    'quests': quests?.map((value) => value.toJson()).toList(growable: false),
    'guildData': guildData?.toJson(),
    'leaderboards': leaderboards.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'activities': activities
        ?.take(50)
        .map((value) => value.toMap())
        .toList(growable: false),
  };

  factory FeatureCacheSnapshot.fromJson(Map<String, Object?> json) {
    if (json.integer('schema') != schemaVersion) {
      throw const FormatException('Unsupported feature cache schema.');
    }
    final ownerNik = json.string('ownerNik');
    if (ownerNik.isEmpty) throw const FormatException('Cache owner missing.');
    final statsJson = json.object('stats');
    final guildJson = json.object('guildData');
    final questValues = json['quests'];
    final activityValues = json['activities'];
    final leaderboardValues = json['leaderboards'];
    final leaderboards = <String, LeaderboardData>{};
    if (leaderboardValues is Map) {
      for (final entry in leaderboardValues.entries) {
        if (entry.value is! Map) continue;
        leaderboards[entry.key.toString()] = LeaderboardData.fromJson(
          (entry.value as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
      }
    }
    return FeatureCacheSnapshot(
      ownerNik: ownerNik,
      savedAtMillis: json.integer('savedAtMillis'),
      stats: statsJson == null ? null : UserStats.fromJson(statsJson),
      quests: questValues is List
          ? questValues
                .whereType<Map>()
                .map(
                  (value) => Quest.fromJson(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                    progressResponse: true,
                  ),
                )
                .toList(growable: false)
          : null,
      guildData: guildJson == null ? null : GuildData.fromJson(guildJson),
      leaderboards: Map.unmodifiable(leaderboards),
      activities: activityValues is List
          ? activityValues
                .whereType<Map>()
                .map(
                  (value) => FinalActivity.fromMap(
                    value.map((key, item) => MapEntry(key.toString(), item)),
                  ),
                )
                .where((value) => value.ownerNik == ownerNik)
                .toList(growable: false)
          : null,
    );
  }
}

class JsonFeatureCacheStore implements FeatureCacheStore {
  const JsonFeatureCacheStore({required this.storage});
  final FeatureCacheStorage storage;

  @override
  Future<FeatureCacheSnapshot?> read(String ownerNik) async {
    final key = featureCacheKeyForOwner(ownerNik);
    try {
      final encoded = await storage.read(key);
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) throw const FormatException('Invalid cache.');
      final snapshot = FeatureCacheSnapshot.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (snapshot.ownerNik != ownerNik) {
        await storage.remove(key);
        return null;
      }
      return snapshot;
    } on Object {
      try {
        await storage.remove(key);
      } on Object {
        // Persistent cache is best effort only.
      }
      return null;
    }
  }

  @override
  Future<void> write(FeatureCacheSnapshot snapshot) async {
    try {
      await storage.write(
        featureCacheKeyForOwner(snapshot.ownerNik),
        jsonEncode(snapshot.toJson()),
      );
    } on Object {
      // Backend data remains authoritative when local persistence is blocked.
    }
  }

  @override
  Future<void> clear(String ownerNik) async {
    try {
      await storage.remove(featureCacheKeyForOwner(ownerNik));
    } on Object {
      // Logout/account switching stays isolated by the owner-specific key.
    }
  }
}

String featureCacheKeyForOwner(String ownerNik) {
  final normalized = ownerNik.trim();
  return 'ora.feature_cache_v1.${_ownerFingerprint(normalized)}';
}

String leaderboardCacheKey(LeaderboardScope scope, LeaderboardMetric metric) =>
    '${scope.apiValue}:${metric.apiValue}';

String _ownerFingerprint(String value) {
  var first = 0x811c9dc5;
  var second = 0x9e3779b9;
  for (final byte in utf8.encode(value)) {
    first = ((first ^ byte) * 0x01000193) & 0xffffffff;
    second = ((second ^ byte) * 0x85ebca6b) & 0xffffffff;
  }
  return '${first.toRadixString(16).padLeft(8, '0')}'
      '${second.toRadixString(16).padLeft(8, '0')}';
}

class MemoryFeatureCacheStorage implements FeatureCacheStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class MemoryFeatureCacheStore extends JsonFeatureCacheStore {
  factory MemoryFeatureCacheStore({MemoryFeatureCacheStorage? storage}) {
    final resolved = storage ?? MemoryFeatureCacheStorage();
    return MemoryFeatureCacheStore._(resolved);
  }

  MemoryFeatureCacheStore._(this.memoryStorage) : super(storage: memoryStorage);

  final MemoryFeatureCacheStorage memoryStorage;
}
