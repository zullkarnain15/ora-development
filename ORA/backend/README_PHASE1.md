# Phase 1: Constants & Configuration Extraction

## Overview

Phase 1 restructures the monolithic `Code.gs` file by extracting all constants, configuration definitions, and schema declarations into dedicated, focused modules. This phase creates the foundation for modular architecture.

## Files Created

### 1. **ORA_Constants.gs**
Central location for all application-wide constants organized by functional domain:

- **API & Version Management**: `ORA_API_VERSION`
- **Session Management**: TTL, cache prefixes, property keys
- **Import Token Management**: TTL limits, folder storage, token prefix
- **Import File Limits**: Image size, text length, active token limits, web URL
- **Strava Sync**: Secret property key, lock timeout, batch limits
- **Runtime Cache**: In-memory cache object with all cache types

**Purpose**: Single source of truth for all constant values. Changes to timeouts, limits, or property keys only need to be made here.

### 2. **ORA_ConfigDefinitions.gs**
Schema definitions for all configuration values:

- `MIN_DISTANCE_VALID_RUN_KM`: Quest eligibility threshold
- `XP_PER_KM`: Activity-to-XP conversion rate
- `NICKNAME_MAX_LENGTH`: User nickname constraints
- `ATTENDANCE_ENABLED`: Feature flag for attendance system
- `ATTENDANCE_QR_ENABLED`: Feature flag for QR scanning

**Purpose**: Each config value has:
- `key`: Property name in the Config sheet
- `defaultValue`: Fallback when value is missing/invalid
- `dataType`: Type conversion (NUMBER, BOOLEAN, TEXT)
- `description`: Admin documentation

**Benefits**:
- Centralized defaults prevent hardcoding
- Type safety through explicit definitions
- Clear admin guidance
- Easy to add new config values

### 3. **ORA_SheetSchemas.gs**
Sheet structure definitions:

- `ORA_SHEETS`: Constants for all sheet names (prevents typos)
- `ORA_REQUEST_SNAPSHOT_SHEETS`: Which sheets are snapshotted per-request
- `ORA_HEADERS`: Expected column headers for each sheet

**Purpose**: 
- Schema validation during `setupBackend1()`
- Header mapping for row parsing
- Request-level caching strategy definition

**Benefits**:
- Single source of truth for sheet names
- Schema mismatches caught early
- Enables automatic header mapping

### 4. **ORA_CacheConfig.gs**
Cache configuration and TTL definitions:

- `ORA_MASTER_CACHE_DEFINITIONS`: Per-sheet master data cache TTLs
- `ORA_READ_HEAVY_CACHE`: Guild leaderboard cache config
- `ORA_QUEST_PROGRESS_CACHE`: Quest progress cache config

**Purpose**: Centralized cache strategy allows tuning without code changes.

**Benefits**:
- Easy to adjust cache TTLs based on load
- Clear cache scope documentation
- Enables generation-based invalidation strategy

## Integration Points

These files are loaded first and used throughout the application:

1. **Constants imported by**:
   - All HTTP handlers
   - Cache management functions
   - Session/import token lifecycle
   - Strava sync operations

2. **Configs used by**:
   - Quest eligibility calculations
   - User input validation
   - Feature flag checks
   - XP calculations

3. **Schemas used by**:
   - Sheet validation (`setupBackend1()`)
   - Header mapping (`createHeaderMap_`)
   - Snapshot caching strategy

4. **Cache configs used by**:
   - `getCachedMasterData_`
   - `getCachedGuildLeaderboardData_`
   - `getCachedQuestProgressForParticipant_`
   - Invalidation orchestration

## Load Order

These files must load in this order:

1. `ORA_Constants.gs` (no dependencies)
2. `ORA_ConfigDefinitions.gs` (depends on constants)
3. `ORA_SheetSchemas.gs` (no dependencies)
4. `ORA_CacheConfig.gs` (no dependencies)

## Migration Path from Code.gs

The following sections were extracted:

```javascript
// From Code.gs lines ~1-50
const ORA_API_VERSION = '1.0';
const ORA_SESSION_TTL_SECONDS = 2592000;
// ... moved to ORA_Constants.gs

// From Code.gs lines ~100-200
const ORA_CONFIG_DEFINITIONS = Object.freeze({ ... });
// ... moved to ORA_ConfigDefinitions.gs

// From Code.gs lines ~200-400
const ORA_SHEETS = Object.freeze({ ... });
const ORA_HEADERS = Object.freeze({ ... });
// ... moved to ORA_SheetSchemas.gs

// From Code.gs lines ~400-550
const ORA_MASTER_CACHE_DEFINITIONS = Object.freeze({ ... });
const ORA_READ_HEAVY_CACHE = Object.freeze({ ... });
// ... moved to ORA_CacheConfig.gs
```

## Next Steps (Phase 2)

Phase 2 will extract:
- Utility functions (normalization, validation, conversion)
- Sheet access functions (validated sheet access, header mapping)
- Common data structures and mappers

Phase 3 will follow with:
- API handlers grouped by feature
- Cache management logic
- Session/token management

## Validation Checklist

- [x] All constants properly frozen
- [x] No circular dependencies
- [x] Default values tested
- [x] Config definitions complete
- [x] Sheet schemas match actual implementation
- [x] Cache TTL values reasonable
- [x] Comments explain purpose of each constant
- [x] Ready for Phase 2 extraction

## Configuration Management Best Practices

1. **Always use ORA_CONFIG_DEFINITIONS** for new config values
2. **Freeze objects** to prevent accidental modifications
3. **Document TTL changes** when adjusting cache durations
4. **Test schema changes** with `testBackend1Setup()`
5. **Version cache keys** when invalidation strategy changes
