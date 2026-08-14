enum LoadPhase { idle, loading, ready, error }

class UserStats {
  const UserStats({
    required this.nik,
    required this.nickname,
    required this.division,
    required this.totalActivities,
    required this.totalDistanceKm,
    required this.totalDurationSec,
    required this.totalXp,
    required this.currentLevel,
    required this.currentLevelName,
    required this.nextLevelXp,
    required this.lastActivityId,
    required this.lastActivityAt,
    required this.updatedAt,
  });

  final String nik;
  final String nickname;
  final String division;
  final int totalActivities;
  final double totalDistanceKm;
  final double totalDurationSec;
  final int totalXp;
  final int currentLevel;
  final String currentLevelName;
  final int? nextLevelXp;
  final String lastActivityId;
  final String lastActivityAt;
  final String? updatedAt;

  factory UserStats.fromJson(Map<String, Object?> json) => UserStats(
    nik: json.string('nik'),
    nickname: json.string('nickname'),
    division: json.string('division'),
    totalActivities: json.integer('totalActivities'),
    totalDistanceKm: json.decimal('totalDistanceKm'),
    totalDurationSec: json.decimal('totalDurationSec'),
    totalXp: json.integer('totalXP'),
    currentLevel: json.integer('currentLevel'),
    currentLevelName: json.string('currentLevelName'),
    nextLevelXp: json.nullableInteger('nextLevelXP'),
    lastActivityId: json.string('lastActivityId'),
    lastActivityAt: json.string('lastActivityAt'),
    updatedAt: json.nullableString('updatedAt'),
  );
}

class OraLevel {
  const OraLevel({
    required this.level,
    required this.levelName,
    required this.requiredTotalXp,
  });
  final int level;
  final String levelName;
  final int requiredTotalXp;

  factory OraLevel.fromJson(Map<String, Object?> json) => OraLevel(
    level: json.integer('level'),
    levelName: json.string('levelName'),
    requiredTotalXp: json.integer('requiredTotalXp'),
  );
}

enum QuestVisualState {
  notStarted,
  inProgress,
  claimable,
  claimed,
  unsupported,
  noGuild,
  unknown,
}

class Quest {
  const Quest({
    required this.questId,
    required this.questName,
    required this.questType,
    required this.targetValue,
    required this.unit,
    required this.rewardXp,
    required this.periodType,
    required this.startDate,
    required this.endDate,
    this.progress,
    this.progressPercent,
    this.status,
    this.completed = false,
    this.claimable,
    this.claimBlockedReason,
    this.claimed = false,
    this.claimId,
    this.claimedAt,
  });

  final String questId;
  final String questName;
  final String questType;
  final double targetValue;
  final String unit;
  final int rewardXp;
  final String periodType;
  final String startDate;
  final String endDate;
  final double? progress;
  final double? progressPercent;
  final String? status;
  final bool completed;
  final bool? claimable;
  final String? claimBlockedReason;
  final bool claimed;
  final String? claimId;
  final String? claimedAt;

  QuestVisualState get visualState {
    if (claimed) return QuestVisualState.claimed;
    if (status == 'UNSUPPORTED_GROUP_SCOPE') {
      return QuestVisualState.unsupported;
    }
    if (status == 'NO_GUILD') return QuestVisualState.noGuild;
    if (status == 'UNKNOWN_TYPE') return QuestVisualState.unknown;
    if (completed) return QuestVisualState.claimable;
    if ((progress ?? 0) > 0) return QuestVisualState.inProgress;
    return QuestVisualState.notStarted;
  }

  bool get canClaim =>
      completed &&
      !claimed &&
      claimable != false &&
      status != 'UNKNOWN_TYPE' &&
      status != 'UNSUPPORTED_GROUP_SCOPE' &&
      status != 'NO_GUILD' &&
      claimBlockedReason != 'GUILD_REWARD_NOT_READY';

  Quest withClaim({String? claimId, String? claimedAt}) => Quest(
    questId: questId,
    questName: questName,
    questType: questType,
    targetValue: targetValue,
    unit: unit,
    rewardXp: rewardXp,
    periodType: periodType,
    startDate: startDate,
    endDate: endDate,
    progress: progress,
    progressPercent: progressPercent,
    status: status,
    completed: completed,
    claimable: false,
    claimBlockedReason: claimBlockedReason,
    claimed: true,
    claimId: claimId,
    claimedAt: claimedAt,
  );

  factory Quest.fromJson(
    Map<String, Object?> json, {
    bool progressResponse = false,
  }) => Quest(
    questId: json.string('questId'),
    questName: json.stringAny(['name', 'questName']),
    questType: json.stringAny(['type', 'questType']),
    targetValue: json.decimalAny(['target', 'targetValue']),
    unit: json.string('unit'),
    rewardXp: json.integer('rewardXp'),
    periodType: json.stringAny(['period', 'periodType']),
    startDate: json.stringAny(['activeFrom', 'startDate']),
    endDate: json.stringAny(['activeTo', 'endDate']),
    progress: progressResponse ? json.decimal('progress') : null,
    progressPercent: progressResponse
        ? json.decimal('progressPercent').clamp(0, 100)
        : null,
    status: json.nullableString('status'),
    completed: json.boolean('completed'),
    claimable: json.nullableBoolean('claimable'),
    claimBlockedReason: json.nullableString('claimBlockedReason'),
    claimed: json.boolean('claimed'),
    claimId: json.nullableString('claimId'),
    claimedAt: json.nullableString('claimedAt'),
  );
}

class QuestClaim {
  const QuestClaim({
    required this.questId,
    required this.rewardXp,
    required this.status,
    this.claimId,
    this.claimedAt,
  });
  final String questId;
  final int rewardXp;
  final String status;
  final String? claimId;
  final String? claimedAt;

  factory QuestClaim.fromJson(Map<String, Object?> json) => QuestClaim(
    questId: json.string('questId'),
    rewardXp: json.integer('rewardXp'),
    status: json.string('status'),
    claimId: json.nullableString('claimId'),
    claimedAt: json.nullableString('claimedAt'),
  );
}

class GuildSummary {
  const GuildSummary({
    required this.guildId,
    required this.guildName,
    required this.memberCount,
    required this.activeMemberCount,
    required this.totalDistanceKm,
    required this.totalActivities,
    required this.totalXp,
    required this.currentLevel,
    required this.currentLevelName,
    required this.displayName,
    required this.description,
    this.status = 'ACTIVE',
  });
  final String guildId;
  final String guildName;
  final int memberCount;
  final int activeMemberCount;
  final double totalDistanceKm;
  final int totalActivities;
  final int totalXp;
  final int currentLevel;
  final String currentLevelName;
  final String displayName;
  final String description;
  final String status;

  String get resolvedName => displayName.isNotEmpty
      ? displayName
      : (guildName.isNotEmpty ? guildName : guildId);

  factory GuildSummary.fromJson(Map<String, Object?> json) => GuildSummary(
    guildId: json.string('guildId'),
    guildName: json.string('guildName'),
    memberCount: json.integer('memberCount'),
    activeMemberCount: json.integer('activeMemberCount'),
    totalDistanceKm: json.decimal('totalDistanceKm'),
    totalActivities: json.integer('totalActivities'),
    totalXp: json.integer('totalXP'),
    currentLevel: json.integer('currentLevel', fallback: 1),
    currentLevelName: json.string('currentLevelName'),
    displayName: json.string('displayName'),
    description: json.string('description'),
    status: json.string('status', fallback: 'ACTIVE'),
  );
}

class GuildMember {
  const GuildMember({
    required this.nik,
    required this.nickname,
    required this.division,
    required this.totalDistanceKm,
    required this.totalActivities,
    required this.totalXp,
    required this.currentLevel,
    required this.currentLevelName,
  });
  final String nik;
  final String nickname;
  final String division;
  final double totalDistanceKm;
  final int totalActivities;
  final int totalXp;
  final int currentLevel;
  final String currentLevelName;

  factory GuildMember.fromJson(Map<String, Object?> json) => GuildMember(
    nik: json.string('nik'),
    nickname: json.string('nickname'),
    division: json.string('division'),
    totalDistanceKm: json.decimal('totalDistanceKm'),
    totalActivities: json.integer('totalActivities'),
    totalXp: json.integer('totalXP'),
    currentLevel: json.integer('currentLevel', fallback: 1),
    currentLevelName: json.string('currentLevelName'),
  );
}

class GuildData {
  const GuildData({
    required this.status,
    required this.guild,
    required this.members,
    required this.directory,
  });
  final String status;
  final GuildSummary? guild;
  final List<GuildMember> members;
  final List<GuildSummary> directory;
}

enum LeaderboardScope { global, guild }

enum LeaderboardMetric { totalXp, totalDistance, totalActivities }

extension LeaderboardScopeApi on LeaderboardScope {
  String get apiValue => this == LeaderboardScope.global ? 'GLOBAL' : 'GUILD';
}

extension LeaderboardMetricApi on LeaderboardMetric {
  String get apiValue => switch (this) {
    LeaderboardMetric.totalXp => 'TOTAL_XP',
    LeaderboardMetric.totalDistance => 'TOTAL_DISTANCE',
    LeaderboardMetric.totalActivities => 'TOTAL_ACTIVITIES',
  };
  String get label => switch (this) {
    LeaderboardMetric.totalXp => 'XP',
    LeaderboardMetric.totalDistance => 'DISTANCE',
    LeaderboardMetric.totalActivities => 'RUNS',
  };
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.nik,
    required this.nickname,
    required this.division,
    required this.totalXp,
    required this.totalDistanceKm,
    required this.totalActivities,
    required this.currentLevel,
    required this.currentLevelName,
  });
  final int rank;
  final String nik;
  final String nickname;
  final String division;
  final int totalXp;
  final double totalDistanceKm;
  final int totalActivities;
  final int currentLevel;
  final String currentLevelName;

  factory LeaderboardEntry.fromJson(Map<String, Object?> json, int index) =>
      LeaderboardEntry(
        rank: json.integer('rank', fallback: index + 1),
        nik: json.string('nik'),
        nickname: json.string('nickname'),
        division: json.string('division'),
        totalXp: json.integer('totalXP'),
        totalDistanceKm: json.decimal('totalDistanceKm'),
        totalActivities: json.integer('totalActivities'),
        currentLevel: json.integer('currentLevel', fallback: 1),
        currentLevelName: json.string('currentLevelName'),
      );
}

class CurrentUserRank {
  const CurrentUserRank({required this.rank, required this.metricValue});
  final int rank;
  final double metricValue;
}

class LeaderboardData {
  const LeaderboardData({
    required this.scope,
    required this.metric,
    required this.status,
    required this.entries,
    required this.currentUserRank,
  });
  final LeaderboardScope scope;
  final LeaderboardMetric metric;
  final String status;
  final List<LeaderboardEntry> entries;
  final CurrentUserRank? currentUserRank;
}

extension JsonValues on Map<String, Object?> {
  String string(String key, {String fallback = ''}) {
    final value = this[key];
    return value == null || value == 'null'
        ? fallback
        : value.toString().trim();
  }

  String stringAny(List<String> keys) {
    for (final key in keys) {
      final value = string(key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String? nullableString(String key) {
    final value = string(key);
    return value.isEmpty ? null : value;
  }

  double decimal(String key, {double fallback = 0}) {
    final value = this[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double decimalAny(List<String> keys) {
    for (final key in keys) {
      if (containsKey(key)) return decimal(key);
    }
    return 0;
  }

  int integer(String key, {int fallback = 0}) =>
      decimal(key, fallback: fallback.toDouble()).toInt();

  int? nullableInteger(String key) => this[key] == null ? null : integer(key);

  bool boolean(String key, {bool fallback = false}) {
    final value = this[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  bool? nullableBoolean(String key) => this[key] == null ? null : boolean(key);

  Map<String, Object?>? object(String key) {
    final value = this[key];
    return value is Map<String, Object?> ? value : null;
  }

  List<Map<String, Object?>> objects(String key) {
    final value = this[key];
    if (value is! List) return const [];
    return value.whereType<Map<String, Object?>>().toList(growable: false);
  }
}
