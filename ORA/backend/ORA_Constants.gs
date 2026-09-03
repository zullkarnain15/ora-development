/**
 * ORA_Constants.gs
 * Central location for all application-wide constants.
 * These values define API version, session management, timeouts, and service limits.
 */

// ============================================================================
// API & VERSION MANAGEMENT
// ============================================================================

/** API version for backward compatibility tracking */
const ORA_API_VERSION = '1.0';

// ============================================================================
// SESSION MANAGEMENT
// ============================================================================

/** Session TTL: 30 days (in seconds) */
const ORA_SESSION_TTL_SECONDS = 2592000;

/** Apps Script cache maximum: 6 hours (in seconds) */
const ORA_SESSION_CACHE_TTL_SECONDS = 21600;

/** Script Properties prefix for session tokens */
const ORA_SESSION_PROPERTY_PREFIX = 'ora_session_';

/** Script Property key for storing ORA spreadsheet ID */
const ORA_SPREADSHEET_ID_PROPERTY = 'ORA_SPREADSHEET_ID';

// ============================================================================
// IMPORT TOKEN MANAGEMENT
// ============================================================================

/** Import token TTL: 10 minutes (in seconds) */
const ORA_IMPORT_TOKEN_TTL_SECONDS = 600;

/** Script Properties prefix for import tokens */
const ORA_IMPORT_TOKEN_PROPERTY_PREFIX = 'ora_import_';

/** Script Property key for import folder storage location */
const ORA_IMPORT_FOLDER_ID_PROPERTY = 'ORA_IMPORT_FOLDER_ID';

// ============================================================================
// IMPORT FILE LIMITS
// ============================================================================

/** Maximum image file size: 2 MB */
const ORA_IMPORT_MAX_IMAGE_BYTES = 2 * 1024 * 1024;

/** Maximum shared text length: 20,000 characters */
const ORA_IMPORT_MAX_TEXT_LENGTH = 20000;

/** Maximum active import tokens: 100 */
const ORA_IMPORT_MAX_ACTIVE = 100;

/** Base URL for import web interface with token parameter */
const ORA_IMPORT_WEB_URL = 'https://zullkarnain15.github.io/ora-development/?t=';

// ============================================================================
// STRAVA SYNC
// ============================================================================

/** Script Property key for Strava sync secret */
const ORA_STRAVA_SYNC_SECRET_PROPERTY = 'ORA_STRAVA_SYNC_SECRET';

/** Strava sync operation lock timeout: 30 seconds */
const ORA_STRAVA_SYNC_LOCK_TIMEOUT_MS = 30000;

/** Maximum activities per Strava sync batch: 500 */
const ORA_STRAVA_SYNC_MAX_ACTIVITIES = 500;

// ============================================================================
// RUNTIME CACHE
// ============================================================================

/**
 * Request-scoped in-memory cache.
 * Apps Script service calls are comparatively expensive. This cache lives only
 * for the current execution and prevents repeated spreadsheet opens/schema reads.
 */
const ORA_RUNTIME_CACHE = {
  // Core spreadsheet reference
  spreadsheet: null,

  // Sheet access cache (prevents repeated getSheetByName calls)
  validatedSheets: {},

  // Request sheet snapshot cache (prevents repeated getValues/getDisplayValues)
  sheetSnapshots: {},
  sheetSnapshotLoads: {},

  // Master data cache (Config, Levels, Quests, etc.)
  masterData: {},
  masterCacheStats: {},

  // Guild leaderboard read-heavy cache
  readHeavyData: {},
  readHeavyCacheStats: {},
  readHeavyGeneration: null,
  readHeavyScopedGenerations: {},

  // Quest progress read-heavy cache
  questProgressData: {},
  questProgressCacheStats: {},
  questProgressGeneration: null,
  questProgressScopedGenerations: {},
};
