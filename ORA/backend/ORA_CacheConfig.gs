/**
 * ORA_CacheConfig.gs
 * Cache configuration including TTLs, key prefixes, and invalidation strategies.
 */

/**
 * Master data cache definitions.
 * These sheets are cached via Apps Script CacheService with defined TTLs.
 * Schema: { sheetName: { key: 'cache_key', ttlSeconds: number } }
 */
const ORA_MASTER_CACHE_DEFINITIONS = Object.freeze({
  Config: Object.freeze({ key: 'ora_master_v1_config', ttlSeconds: 300 }),
  Level_Master: Object.freeze({ key: 'ora_master_v1_levels', ttlSeconds: 600 }),
  Quest_Master: Object.freeze({ key: 'ora_master_v1_quests', ttlSeconds: 180 }),
  Guild_Master: Object.freeze({ key: 'ora_master_v1_guilds', ttlSeconds: 300 }),
  Attendance_Reward_Master: Object.freeze({
    key: 'ora_master_v1_attendance_rewards',
    ttlSeconds: 300,
  }),
});

/**
 * Read-heavy cache configuration for guild leaderboards and guild data.
 * Used for caching expensive multi-sheet aggregation queries.
 * Cache keys incorporate generation versioning for invalidation.
 */
const ORA_READ_HEAVY_CACHE = Object.freeze({
  prefix: 'ora_read_v1',
  generationKey: 'ora_read_v1_generation',
  ttlSeconds: 60,
  generationTtlSeconds: 21600, // 6 hours
});

/**
 * Quest progress cache configuration.
 * Quest progress is calculated from several high-cardinality sheets.
 * Cache keys incorporate member and guild scoping for isolation.
 * Cache values are short-lived; invalidation rotates generation immediately.
 */
const ORA_QUEST_PROGRESS_CACHE = Object.freeze({
  prefix: 'ora_quest_progress_v1',
  generationKey: 'ora_quest_progress_v1_generation',
  ttlSeconds: 60,
  generationTtlSeconds: 21600, // 6 hours
});
