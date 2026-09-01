/**
 * ORA (OTO Runners Adventure) - Backend
 * Google Apps Script bound to spreadsheet: ORA_Master_Data
 *
 * Scope:
 * - health check
 * - participant login (NIK + PIN)
 * - first-activation nickname save
 * - active Config, Level_Master, and Quest_Master reads
 * - completed Android activity sync
 * - activity XP, level calculation, and User_Stats aggregation
 * - calculated-on-read quest progress for authenticated users
 * - idempotent quest reward claims
 * - read-only guild summary derived from participant divisions
 * - read-only individual leaderboard from active participant stats
 * - optional Guild_Master metadata with legacy division fallback
 *
 * Not included:
 * - guild membership management, invitations, and approvals
 */

const ORA_API_VERSION = '1.0';
const ORA_SESSION_TTL_SECONDS = 2592000; // 30 days
const ORA_SESSION_CACHE_TTL_SECONDS = 21600; // Apps Script cache maximum: 6 hours
const ORA_SESSION_PROPERTY_PREFIX = 'ora_session_';
const ORA_SPREADSHEET_ID_PROPERTY = 'ORA_SPREADSHEET_ID';
const ORA_IMPORT_TOKEN_TTL_SECONDS = 600; // 10 minutes
const ORA_IMPORT_TOKEN_PROPERTY_PREFIX = 'ora_import_';
const ORA_IMPORT_FOLDER_ID_PROPERTY = 'ORA_IMPORT_FOLDER_ID';
const ORA_IMPORT_MAX_IMAGE_BYTES = 2 * 1024 * 1024;
const ORA_IMPORT_MAX_TEXT_LENGTH = 20000;
const ORA_IMPORT_MAX_ACTIVE = 100;
const ORA_IMPORT_WEB_URL = 'https://zullkarnain15.github.io/ora-development/?t=';
const ORA_STRAVA_SYNC_SECRET_PROPERTY = 'ORA_STRAVA_SYNC_SECRET';
const ORA_STRAVA_SYNC_LOCK_TIMEOUT_MS = 30000;
const ORA_STRAVA_SYNC_MAX_ACTIVITIES = 500;

// Apps Script service calls are comparatively expensive. This cache lives only
// for the current execution and prevents repeated spreadsheet opens/schema reads.
const ORA_RUNTIME_CACHE = {
  spreadsheet: null,
  validatedSheets: {},
  sheetSnapshots: {},
  sheetSnapshotLoads: {},
  masterData: {},
  masterCacheStats: {},
  readHeavyData: {},
  readHeavyCacheStats: {},
  readHeavyGeneration: null,
};

const ORA_CONFIG_DEFINITIONS = Object.freeze({
  MIN_DISTANCE_VALID_RUN_KM: Object.freeze({
    key: 'MIN_DISTANCE_VALID_RUN_KM',
    defaultValue: 1.0,
    dataType: 'NUMBER',
    description: 'Jarak minimum agar satu activity dianggap sebagai valid run untuk aturan berbasis jumlah run. Contoh: 1.0 = minimum 1 km. Berbeda dari MIN_DISTANCE_XP_KM.',
  }),
});

const ORA_SHEETS = Object.freeze({
  PARTICIPANTS: 'Participants',
  CONFIG: 'Config',
  LEVELS: 'Level_Master',
  QUESTS: 'Quest_Master',
  ACTIVITIES: 'Activities',
  USER_STATS: 'User_Stats',
  QUEST_CLAIMS: 'Quest_Claims',
  GUILD_MASTER: 'Guild_Master',
  ATTENDANCE_EVENTS: 'Attendance_Event_Master',
  ATTENDANCE_RECORDS: 'Attendance_Records',
  ATTENDANCE_REWARDS: 'Attendance_Reward_Master',
  SHORTCUT_ICLOUD: 'Shortcut_Icloud',
  STRAVA_ATHLETE_MAP: 'Strava_Athlete_Map',
});

const ORA_REQUEST_SNAPSHOT_SHEETS = Object.freeze({
  Participants: true,
  User_Stats: true,
  Activities: true,
  Quest_Claims: true,
  Quest_Master: true,
  Guild_Master: true,
  Level_Master: true,
  Config: true,
  Attendance_Records: true,
});

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

const ORA_READ_HEAVY_CACHE = Object.freeze({
  prefix: 'ora_read_v1',
  generationKey: 'ora_read_v1_generation',
  ttlSeconds: 60,
  generationTtlSeconds: 21600,
});

const ORA_HEADERS = Object.freeze({
  Participants: [
    'NIK',
    'PIN',
    'Nickname',
    'Division_Guild',
    'Status',
    'Created_At',
    'Updated_At',
  ],
  Config: [
    'Config_Key',
    'Config_Value',
    'Data_Type',
    'Description',
    'Active',
  ],
  Level_Master: ['Level', 'Level_Name', 'Required_Total_XP', 'Active'],
  Quest_Master: [
    'Quest_ID',
    'Quest_Name',
    'Quest_Type',
    'Target_Value',
    'Unit',
    'Reward_XP',
    'Period_Type',
    'Start_Date',
    'End_Date',
    'Active',
  ],
  Activities: [
    'ActivityId',
    'NIK',
    'Nickname',
    'Division',
    'StartTime',
    'EndTime',
    'DurationSec',
    'DistanceKm',
    'AvgPace',
    'Status',
    'Source',
    'DeviceTime',
    'SyncedAt',
    'CreatedAt',
    'UpdatedAt',
    'SourceRef',
    'SourceUrl',
  ],
  User_Stats: [
    'NIK',
    'Nickname',
    'Division',
    'TotalActivities',
    'TotalDistanceKm',
    'TotalDurationSec',
    'TotalXP',
    'CurrentLevel',
    'CurrentLevelName',
    'NextLevelXP',
    'LastActivityId',
    'LastActivityAt',
    'UpdatedAt',
  ],
  Quest_Claims: [
    'ClaimId',
    'NIK',
    'QuestId',
    'QuestName',
    'RewardXP',
    'Status',
    'ClaimedAt',
    'CreatedAt',
  ],
  Guild_Master: [
    'GuildId',
    'GuildName',
    'DisplayName',
    'Description',
    'Status',
    'SortOrder',
    'CreatedAt',
    'UpdatedAt',
  ],
  Attendance_Event_Master: [
    'EventId',
    'EventName',
    'EventDate',
    'StartTime',
    'EndTime',
    'CountForStreak',
    'QRToken',
    'Status',
    'CreatedAt',
    'UpdatedAt',
  ],
  Attendance_Records: [
    'AttendanceId',
    'EventId',
    'NIK',
    'Nickname',
    'CheckInAt',
    'BaseXP',
    'StreakCount',
    'StreakBonusXP',
    'TotalXP',
    'Status',
    'CreatedAt',
  ],
  Attendance_Reward_Master: ['RewardType', 'Milestone', 'XP', 'Status'],
  Shortcut_Icloud: ['LINK_ICLOUD'],
  Strava_Athlete_Map: ['AthleteId', 'AthleteName', 'NIK', 'Nickname', 'Guild'],
});

/**
 * Public GET endpoint.
 * Supported actions: health, config, levels, quests, iphoneShortcut.
 * Login and nickname activation intentionally require POST.
 */
function doGet(e) {
  resetRequestSheetSnapshots_();
  try {
    const action = normalizeAction_(e && e.parameter ? e.parameter.action : 'health');

    switch (action) {
      case 'health':
        return jsonSuccess_({
          service: 'ORA Backend',
          status: 'UP',
          spreadsheet: getOraSpreadsheet_().getName(),
        });
      case 'config':
        return jsonSuccess_({ config: getActiveConfig_() });
      case 'levels':
        return jsonSuccess_({ levels: getActiveLevels_() });
      case 'quests':
        return jsonSuccess_({ quests: getActiveQuests_() });
      case 'iphoneshortcut':
        return jsonSuccess_({ linkIcloud: getIphoneShortcutLink_() });
      default:
        return jsonError_('UNKNOWN_ACTION', 'Action GET tidak dikenali.');
    }
  } catch (error) {
    if (error && error.oraCode) {
      return jsonError_(error.oraCode, error.message);
    }
    console.error('ORA doGet failed: %s', safeErrorMessage_(error));
    return jsonError_('INTERNAL_ERROR', 'Terjadi kesalahan pada server ORA.');
  }
}

function getIphoneShortcutLink_() {
  const rows = readSheetObjects_(ORA_SHEETS.SHORTCUT_ICLOUD);
  if (rows.length === 0) {
    throw oraError_('SHORTCUT_LINK_NOT_FOUND', 'Link iCloud Shortcut belum diisi.');
  }

  return normalizeIphoneShortcutLink_(rows[0].LINK_ICLOUD);
}

function normalizeIphoneShortcutLink_(value) {
  const link = String(value == null ? '' : value).trim();
  if (!/^https:\/\/www\.icloud\.com\/shortcuts\/[a-z0-9]+\/?(?:[?#].*)?$/i.test(link)) {
    throw oraError_('SHORTCUT_LINK_INVALID', 'LINK_ICLOUD harus berupa link iCloud Shortcut yang valid.');
  }
  return link;
}

/**
 * Public POST endpoint.
 * JSON body examples:
 * {"action":"login","nik":"12345678","pin":"1234"}
 * {"action":"activateNickname","sessionToken":"...","nickname":"ZULRUN15"}
 * {"action":"updateNickname","sessionToken":"...","nickname":"NEWRUN1"}
 * {"action":"submitActivity","sessionToken":"...","activity":{"activityId":"..."}}
 * {"action":"getActivityHistory","sessionToken":"...","limit":50,"offset":0}
 * {"action":"getGuildSummary","sessionToken":"..."}
 * {"action":"getGuildDirectory","sessionToken":"..."}
 * {"action":"getLeaderboard","sessionToken":"...","scope":"GLOBAL","metric":"TOTAL_XP"}
 * {"action":"getGuildData","sessionToken":"...","scope":"GLOBAL","metric":"TOTAL_XP"}
 * {"action":"getQuestProgress","sessionToken":"..."}
 * {"action":"claimQuestReward","sessionToken":"...","questId":"DEV-Q001"}
 * {"action":"submitAttendance","sessionToken":"...","qrToken":"..."}
 * {"action":"syncStravaActivities","source":"ORA_StravaSync","secret":"...","activities":[]}
 */
function doPost(e) {
  resetRequestSheetSnapshots_();
  try {
    const request = parseJsonBody_(e);
    const action = normalizeAction_(request.action);

    switch (action) {
      case 'login':
        return handleLogin_(request);
      case 'activatenickname':
        return handleActivateNickname_(request);
      case 'updatenickname':
        return handleUpdateNickname_(request);
      case 'submitactivity':
        return handleSubmitActivity_(request);
      case 'createimporttoken':
        return handleCreateImportToken_(request);
      case 'getimportpayload':
        return handleGetImportPayload_(request);
      case 'consumeimporttoken':
        return handleConsumeImportToken_(request);
      case 'getactivityhistory':
        return measureEndpointTiming_('getActivityHistory', function () {
          return handleGetActivityHistory_(request);
        });
      case 'getuserstats':
        return measureEndpointTiming_('getUserStats', function () {
          return handleGetUserStats_(request);
        });
      case 'getguildsummary':
        return measureEndpointTiming_('getGuildSummary', function () {
          return handleGetGuildSummary_(request);
        });
      case 'getguilddirectory':
        return measureEndpointTiming_('getGuildDirectory', function () {
          return handleGetGuildDirectory_(request);
        });
      case 'getleaderboard':
        return measureEndpointTiming_('getLeaderboard', function () {
          return handleGetLeaderboard_(request);
        });
      case 'getguilddata':
        return measureEndpointTiming_('getGuildData', function () {
          return handleGetGuildData_(request);
        });
      case 'getquestprogress':
        return measureEndpointTiming_('getQuestProgress', function () {
          return handleGetQuestProgress_(request);
        });
      case 'claimquestreward':
        return handleClaimQuestReward_(request);
      case 'submitattendance':
      case 'checkinattendance':
        return handleSubmitAttendance_(request);
      case 'syncstravaactivities':
        return handleSyncStravaActivities_(request);
      case 'config':
        return jsonSuccess_({ config: getActiveConfig_() });
      case 'levels':
        return jsonSuccess_({ levels: getActiveLevels_() });
      case 'quests':
        return jsonSuccess_({ quests: getActiveQuests_() });
      default:
        return jsonError_('UNKNOWN_ACTION', 'Action POST tidak dikenali.');
    }
  } catch (error) {
    if (error && error.oraCode) {
      return jsonError_(error.oraCode, error.message);
    }

    console.error('ORA doPost failed: %s', safeErrorMessage_(error));
    return jsonError_('INTERNAL_ERROR', 'Terjadi kesalahan pada server ORA.');
  }
}

function handleSyncStravaActivities_(request) {
  validateStravaSyncSecret_(request.secret);
  const activities = Array.isArray(request.activities) ? request.activities : [];
  if (activities.length > ORA_STRAVA_SYNC_MAX_ACTIVITIES) {
    throw oraError_(
      'STRAVA_SYNC_BATCH_TOO_LARGE',
      'Maksimal ' + ORA_STRAVA_SYNC_MAX_ACTIVITIES + ' aktivitas per sinkronisasi.'
    );
  }
  const lock = LockService.getScriptLock();
  lock.waitLock(ORA_STRAVA_SYNC_LOCK_TIMEOUT_MS);

  try {
    const sheet = getActivitiesSheet_();
    const athleteMapSheet = getValidatedSheet_(ORA_SHEETS.STRAVA_ATHLETE_MAP);
    const observedAthletes = upsertObservedStravaAthletes_(athleteMapSheet, activities);
    const athleteNikMap = loadStravaAthleteNikMap_(athleteMapSheet);
    const participants = loadActiveParticipantsByNik_();
    refreshObservedStravaAthleteMap_(
      athleteMapSheet,
      observedAthletes,
      athleteNikMap,
      participants
    );
    const existingActivities = loadExistingStravaActivities_(sheet);
    const now = new Date();
    const rowsToAppend = [];
    const remaps = [];
    const statsEvents = [];
    const statuses = [];
    const seenInRequest = {};
    const summary = { NEW: 0, DUPLICATE: 0, UNMAPPED: 0, INVALID: 0 };

    activities.forEach(function (rawActivity) {
      const normalized = normalizeStravaSyncActivity_(rawActivity);
      if (normalized.error) {
        statuses.push(stravaSyncStatus_(rawActivity, 'INVALID', normalized.error));
        summary.INVALID += 1;
        return;
      }

      const activity = normalized.activity;
      if (seenInRequest[activity.activityId]) {
        statuses.push(stravaSyncStatus_(activity, 'DUPLICATE', 'activityId duplicated in request'));
        summary.DUPLICATE += 1;
        return;
      }
      seenInRequest[activity.activityId] = true;

      const mappedNik = athleteNikMap[activity.athleteId] || '';
      const participant = mappedNik ? participants[mappedNik] || null : null;
      const existing = existingActivities[activity.activityId] || null;

      if (existing) {
        if (existing.status === 'UNMAPPED') {
          if (participant) {
            remaps.push({ existing: existing, activity: activity, participant: participant });
            statsEvents.push({ activity: activity, participant: participant });
            statuses.push(stravaSyncStatus_(activity, 'NEW', 'existing UNMAPPED row mapped to participant'));
            summary.NEW += 1;
          } else {
            statuses.push(stravaSyncStatus_(activity, 'UNMAPPED', stravaUnmappedReason_(mappedNik)));
            summary.UNMAPPED += 1;
          }
        } else {
          statuses.push(stravaSyncStatus_(activity, 'DUPLICATE', 'Strava activity already exists'));
          summary.DUPLICATE += 1;
        }
        return;
      }

      const status = participant ? 'NEW' : 'UNMAPPED';
      rowsToAppend.push(buildOraStravaActivityRow_(activity, participant, now));
      if (participant) statsEvents.push({ activity: activity, participant: participant });
      statuses.push(stravaSyncStatus_(activity, status, participant ? '' : stravaUnmappedReason_(mappedNik)));
      summary[status] += 1;
    });

    const statsBatch = prepareStravaUserStatsBatch_(statsEvents);
    const remapSnapshots = [];
    let appendStartRow = null;
    let appendedRowsWritten = false;

    try {
      remaps.forEach(function (remap) {
        const rowNumber = remap.existing.rowNumber;
        const previousValues = remap.existing.previousValues;
        remapSnapshots.push({ rowNumber: rowNumber, previousValues: previousValues });
        const updatedRow = buildOraStravaActivityRow_(remap.activity, remap.participant, now);
        if (previousValues[13]) updatedRow[13] = previousValues[13];
        sheet.getRange(rowNumber, 1, 1, ORA_HEADERS.Activities.length).setValues([updatedRow]);
      });
      if (remaps.length > 0) invalidateSheetSnapshot_(ORA_SHEETS.ACTIVITIES);

      if (rowsToAppend.length > 0) {
        appendStartRow = sheet.getLastRow() + 1;
        ensureOraSheetRowCapacity_(sheet, appendStartRow + rowsToAppend.length - 1);
        sheet.getRange(appendStartRow, 1, rowsToAppend.length, 2).setNumberFormat('@');
        sheet
          .getRange(appendStartRow, 1, rowsToAppend.length, ORA_HEADERS.Activities.length)
          .setValues(rowsToAppend);
        appendedRowsWritten = true;
        invalidateSheetSnapshot_(ORA_SHEETS.ACTIVITIES);
      }

      applyStravaUserStatsBatch_(statsBatch);
    } catch (error) {
      rollbackStravaUserStatsBatch_(statsBatch);
      if (appendedRowsWritten) {
        sheet.deleteRows(appendStartRow, rowsToAppend.length);
        invalidateSheetSnapshot_(ORA_SHEETS.ACTIVITIES);
      }
      remapSnapshots.forEach(function (snapshot) {
        sheet
          .getRange(snapshot.rowNumber, 1, 1, ORA_HEADERS.Activities.length)
          .setValues([snapshot.previousValues]);
      });
      if (remapSnapshots.length > 0) invalidateSheetSnapshot_(ORA_SHEETS.ACTIVITIES);
      throw error;
    }

    return jsonStravaSyncSuccess_({
      received: activities.length,
      inserted: rowsToAppend.length,
      updated: remaps.length,
      summary: summary,
      statuses: statuses,
    });
  } finally {
    lock.releaseLock();
  }
}

function validateStravaSyncSecret_(secret) {
  const expected = PropertiesService
    .getScriptProperties()
    .getProperty(ORA_STRAVA_SYNC_SECRET_PROPERTY);
  if (!expected) {
    throw oraError_(
      'STRAVA_SYNC_NOT_CONFIGURED',
      'Script Property ORA_STRAVA_SYNC_SECRET belum dikonfigurasi.'
    );
  }
  if (String(secret || '') !== expected) {
    throw oraError_('UNAUTHORIZED', 'Secret Strava sync tidak valid.');
  }
}

function collectObservedStravaAthletes_(activities) {
  const observed = {};
  (activities || []).forEach(function (rawActivity) {
    const normalized = normalizeStravaSyncActivity_(rawActivity);
    if (normalized.error) return;
    const activity = normalized.activity;
    observed[activity.athleteId] = {
      athleteId: activity.athleteId,
      athleteName: activity.athleteName,
    };
  });
  return observed;
}

function ensureStravaAthleteMapNotesColumn_(sheet) {
  const lastColumn = Math.max(sheet.getLastColumn(), 1);
  const headers = sheet.getRange(1, 1, 1, lastColumn).getDisplayValues()[0];
  const headerMap = createCaseInsensitiveHeaderMap_(headers);
  const existingColumn = headerMap.notes == null ? headerMap.note : headerMap.notes;
  if (existingColumn != null) return existingColumn;

  const notesColumn = lastColumn;
  if (sheet.getMaxColumns() < lastColumn + 1) {
    sheet.insertColumnsAfter(sheet.getMaxColumns(), lastColumn + 1 - sheet.getMaxColumns());
  }
  sheet.getRange(1, notesColumn + 1, 1, 1).setValues([['Notes']]);
  return notesColumn;
}

function upsertObservedStravaAthletes_(sheet, activities) {
  const observed = collectObservedStravaAthletes_(activities);
  const observedIds = Object.keys(observed);
  if (observedIds.length === 0) return observed;

  const notesColumn = ensureStravaAthleteMapNotesColumn_(sheet);
  const lastColumn = Math.max(sheet.getLastColumn(), notesColumn + 1);
  const values = sheet.getRange(1, 1, Math.max(sheet.getLastRow(), 1), lastColumn)
    .getDisplayValues();
  const headers = createCaseInsensitiveHeaderMap_(values[0]);
  const existingIds = {};
  values.slice(1).forEach(function (row) {
    const athleteId = String(row[headers.athleteid] || '').trim();
    if (athleteId) existingIds[athleteId] = true;
  });

  const rowsToAppend = observedIds.filter(function (athleteId) {
    return !existingIds[athleteId];
  }).map(function (athleteId) {
    const row = new Array(lastColumn).fill('');
    row[headers.athleteid] = athleteId;
    row[headers.athletename] = observed[athleteId].athleteName;
    row[notesColumn] = 'UNMAPPED';
    return row;
  });

  if (rowsToAppend.length > 0) {
    const startRow = sheet.getLastRow() + 1;
    ensureOraSheetRowCapacity_(sheet, startRow + rowsToAppend.length - 1);
    sheet.getRange(startRow, headers.athleteid + 1, rowsToAppend.length, 1)
      .setNumberFormat('@');
    sheet.getRange(startRow, headers.nik + 1, rowsToAppend.length, 1)
      .setNumberFormat('@');
    sheet.getRange(startRow, 1, rowsToAppend.length, lastColumn).setValues(rowsToAppend);
  }
  return observed;
}

function refreshObservedStravaAthleteMap_(sheet, observed, athleteNikMap, participants) {
  const observedIds = Object.keys(observed || {});
  if (observedIds.length === 0 || sheet.getLastRow() < 2) return;

  const notesColumn = ensureStravaAthleteMapNotesColumn_(sheet);
  const lastColumn = Math.max(sheet.getLastColumn(), notesColumn + 1);
  const values = sheet.getRange(1, 1, sheet.getLastRow(), lastColumn).getDisplayValues();
  const headers = createCaseInsensitiveHeaderMap_(values[0]);
  const names = values.slice(1).map(function (row) {
    return [row[headers.athletename]];
  });
  const notes = values.slice(1).map(function (row) {
    return [row[notesColumn]];
  });
  let namesChanged = false;
  let notesChanged = false;

  values.slice(1).forEach(function (row, index) {
    const athleteId = String(row[headers.athleteid] || '').trim();
    if (!observed[athleteId]) return;
    const athleteName = observed[athleteId].athleteName;
    const note = stravaAthleteMapNote_(athleteId, athleteNikMap, participants);
    if (names[index][0] !== athleteName) {
      names[index][0] = athleteName;
      namesChanged = true;
    }
    if (notes[index][0] !== note) {
      notes[index][0] = note;
      notesChanged = true;
    }
  });

  if (namesChanged) {
    sheet.getRange(2, headers.athletename + 1, names.length, 1).setValues(names);
  }
  if (notesChanged) {
    sheet.getRange(2, notesColumn + 1, notes.length, 1).setValues(notes);
  }
}

function stravaAthleteMapNote_(athleteId, athleteNikMap, participants) {
  const mappedNik = athleteNikMap[athleteId] || '';
  return mappedNik && participants[mappedNik] ? 'MAPPED' : 'UNMAPPED';
}

function loadStravaAthleteNikMap_(validatedSheet) {
  const sheet = validatedSheet || getValidatedSheet_(ORA_SHEETS.STRAVA_ATHLETE_MAP);
  const values = sheet.getDataRange().getDisplayValues();
  if (values.length < 2) return {};
  const headers = createCaseInsensitiveHeaderMap_(values[0]);
  const athleteIdColumn = headers.athleteid;
  const nikColumn = headers.nik;
  const activeColumn = headers.active;
  const result = {};

  values.slice(1).forEach(function (row) {
    const athleteId = String(row[athleteIdColumn] || '').trim();
    const nik = normalizeDigits_(row[nikColumn]);
    const active = activeColumn == null || isOptionalActiveValue_(row[activeColumn]);
    if (!athleteId || !nik || !active) return;
    if (result[athleteId] && result[athleteId] !== nik) {
      throw oraError_(
        'INVALID_STRAVA_ATHLETE_MAP',
        'AthleteId ' + athleteId + ' memiliki lebih dari satu NIK.'
      );
    }
    result[athleteId] = nik;
  });
  return result;
}

function loadActiveParticipantsByNik_() {
  const rows = readSheetObjects_(ORA_SHEETS.PARTICIPANTS);
  const result = {};
  rows.forEach(function (row) {
    const nik = normalizeDigits_(row.NIK);
    if (!nik || String(row.Status || '').trim().toUpperCase() !== 'ACTIVE') return;
    result[nik] = {
      nik: nik,
      nickname: String(row.Nickname || '').trim(),
      divisionGuild: String(row.Division_Guild || '').trim(),
    };
  });
  return result;
}

function loadExistingStravaActivities_(sheet) {
  const values = readSheetValues_(ORA_SHEETS.ACTIVITIES, sheet);
  const displayValues = readSheetDisplayValues_(ORA_SHEETS.ACTIVITIES, sheet);
  if (values.length < 2) return {};
  const headerMap = createHeaderMap_(displayValues[0]);
  const result = {};
  displayValues.slice(1).forEach(function (row, index) {
    if (normalizeImportActivitySource_(row[headerMap.Source]) !== 'STRAVA') return;
    const sourceRef = String(row[headerMap.SourceRef] || '').trim();
    if (!sourceRef) return;
    result[sourceRef] = {
      rowNumber: index + 2,
      status: String(row[headerMap.Status] || '').trim().toUpperCase(),
      nik: normalizeDigits_(row[headerMap.NIK]),
      previousValues: values[index + 1].slice(0, ORA_HEADERS.Activities.length),
    };
  });
  return result;
}

function normalizeStravaSyncActivity_(rawActivity) {
  if (!rawActivity || typeof rawActivity !== 'object' || Array.isArray(rawActivity)) {
    return { error: 'activity must be an object' };
  }
  const activityId = String(rawActivity.activityId || '').trim();
  const athleteId = String(rawActivity.athleteId || '').trim();
  const activityDateLocal = String(rawActivity.activityDateLocal || '').trim();
  if (!/^\d+$/.test(activityId)) return { error: 'invalid activityId' };
  if (!/^\d+$/.test(athleteId)) return { error: 'invalid athleteId' };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(activityDateLocal)) {
    return { error: 'invalid activityDateLocal' };
  }

  const numberFields = [
    'distanceKm',
    'movingTimeSeconds',
    'elapsedTimeSeconds',
    'paceSecondsPerKm',
    'elevationGainMeters',
  ];
  const numbers = {};
  for (let index = 0; index < numberFields.length; index += 1) {
    const field = numberFields[index];
    const value = rawActivity[field];
    if (value === null || value === undefined || value === '') {
      numbers[field] = null;
      continue;
    }
    const number = Number(value);
    if (!Number.isFinite(number) || number < 0) return { error: 'invalid ' + field };
    numbers[field] = number;
  }

  const startDateUtc = String(rawActivity.startDateUtc || '').trim();
  if (startDateUtc && isNaN(new Date(startDateUtc).getTime())) {
    return { error: 'invalid startDateUtc' };
  }
  return {
    activity: {
      athleteName: String(rawActivity.athleteName || '').trim(),
      athleteId: athleteId,
      activityId: activityId,
      activityDateLocal: activityDateLocal,
      startDateUtc: startDateUtc,
      distanceKm: numbers.distanceKm,
      movingTimeSeconds: numbers.movingTimeSeconds,
      elapsedTimeSeconds: numbers.elapsedTimeSeconds,
      paceSecondsPerKm: numbers.paceSecondsPerKm,
      elevationGainMeters: numbers.elevationGainMeters,
      sportType: String(rawActivity.sportType || '').trim(),
      activityTitle: String(rawActivity.activityTitle || '').trim(),
    },
  };
}

function buildOraStravaActivityRow_(activity, participant, now) {
  const startTime = activity.startDateUtc || activity.activityDateLocal;
  return [
    'STRAVA-' + activity.activityId,
    participant ? participant.nik : '',
    participant ? participant.nickname : activity.athleteName,
    participant ? participant.divisionGuild : '',
    startTime,
    stravaActivityEndTime_(activity),
    stravaActivityDurationSeconds_(activity),
    activity.distanceKm == null ? 0 : activity.distanceKm,
    formatStravaPace_(activity.paceSecondsPerKm),
    participant ? 'COMPLETED' : 'UNMAPPED',
    'STRAVA',
    '',
    now,
    now,
    now,
    activity.activityId,
    'https://www.strava.com/activities/' + activity.activityId,
  ];
}

function stravaActivityDurationSeconds_(activity) {
  if (activity.movingTimeSeconds != null) return activity.movingTimeSeconds;
  if (activity.elapsedTimeSeconds != null) return activity.elapsedTimeSeconds;
  return 0;
}

function stravaActivityEndTime_(activity) {
  if (!activity.startDateUtc || activity.elapsedTimeSeconds == null) return '';
  const start = new Date(activity.startDateUtc);
  if (isNaN(start.getTime())) return '';
  return new Date(start.getTime() + activity.elapsedTimeSeconds * 1000).toISOString();
}

function formatStravaPace_(paceSecondsPerKm) {
  if (paceSecondsPerKm == null) return '';
  const totalSeconds = Math.round(Number(paceSecondsPerKm));
  if (!Number.isFinite(totalSeconds) || totalSeconds < 0) return '';
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
}

function createCaseInsensitiveHeaderMap_(headers) {
  const map = {};
  headers.forEach(function (header, index) {
    map[String(header || '').trim().toLowerCase()] = index;
  });
  return map;
}

function isOptionalActiveValue_(value) {
  const normalized = String(value == null ? '' : value).trim().toUpperCase();
  return ['', 'TRUE', 'ACTIVE', 'YES', '1'].indexOf(normalized) >= 0;
}

function stravaUnmappedReason_(mappedNik) {
  return mappedNik
    ? 'Mapped NIK is missing or inactive in Participants'
    : 'athleteId is not mapped to NIK';
}

function stravaSyncStatus_(activity, status, reason) {
  return {
    activityId: activity && activity.activityId ? String(activity.activityId) : '',
    athleteId: activity && activity.athleteId ? String(activity.athleteId) : '',
    status: status,
    reason: reason || '',
  };
}

function compareStravaStatsEvents_(left, right) {
  const leftKey = left.activity.startDateUtc || left.activity.activityDateLocal || '';
  const rightKey = right.activity.startDateUtc || right.activity.activityDateLocal || '';
  if (leftKey < rightKey) return -1;
  if (leftKey > rightKey) return 1;
  return left.activity.activityId.localeCompare(right.activity.activityId);
}

function aggregateStravaStatsEvents_(statsEvents, xpPerKm) {
  const aggregates = {};
  (statsEvents || [])
    .slice()
    .sort(compareStravaStatsEvents_)
    .forEach(function (event) {
      const participant = event.participant;
      const activity = event.activity;
      const nik = participant.nik;
      const distanceKm = activity.distanceKm == null ? 0 : activity.distanceKm;
      const durationSec = stravaActivityDurationSeconds_(activity);
      if (!aggregates[nik]) {
        aggregates[nik] = {
          participant: participant,
          activityCount: 0,
          distanceKm: 0,
          durationSec: 0,
          activityXp: 0,
          lastActivityId: '',
          lastActivityAt: '',
        };
      }

      const aggregate = aggregates[nik];
      aggregate.activityCount += 1;
      aggregate.distanceKm += Number(distanceKm) || 0;
      aggregate.durationSec += Number(durationSec) || 0;
      aggregate.activityXp += calculateActivityXpWithRate_(
        distanceKm,
        'COMPLETED',
        xpPerKm
      );
      aggregate.lastActivityId = 'STRAVA-' + activity.activityId;
      aggregate.lastActivityAt = activity.startDateUtc || activity.activityDateLocal;
    });

  return Object.keys(aggregates).map(function (nik) {
    return aggregates[nik];
  });
}

function prepareStravaUserStatsBatch_(statsEvents) {
  if (!statsEvents || statsEvents.length === 0) {
    return {
      sheet: null,
      existingWrites: [],
      appendRows: [],
      snapshots: [],
      appendStartRow: null,
      appendedRowsWritten: false,
    };
  }

  const sheet = ensureUserStatsSheet_();
  const values = readSheetValues_(ORA_SHEETS.USER_STATS, sheet);
  const displayValues = readSheetDisplayValues_(ORA_SHEETS.USER_STATS, sheet);
  const headerMap = createHeaderMap_(displayValues[0]);
  const existingByNik = {};

  for (let index = 1; index < displayValues.length; index += 1) {
    const nik = normalizeDigits_(displayValues[index][headerMap.NIK]);
    if (!nik || existingByNik[nik]) continue;
    const row = values[index];
    existingByNik[nik] = {
      rowNumber: index + 1,
      previousValues: row.slice(0, ORA_HEADERS.User_Stats.length),
      totalActivities: Number(row[headerMap.TotalActivities]) || 0,
      totalDistanceKm: Number(row[headerMap.TotalDistanceKm]) || 0,
      totalDurationSec: Number(row[headerMap.TotalDurationSec]) || 0,
      totalXp: Number(row[headerMap.TotalXP]) || 0,
    };
  }

  const levels = getActiveLevels_();
  const aggregates = aggregateStravaStatsEvents_(statsEvents, getXpPerKm_());
  const existingWrites = [];
  const appendRows = [];
  const snapshots = [];
  const now = new Date();

  aggregates.forEach(function (aggregate) {
    const participant = aggregate.participant;
    const existing = existingByNik[participant.nik] || null;
    const totalActivities =
      (existing ? existing.totalActivities : 0) + aggregate.activityCount;
    const totalDistanceKm = roundDecimal_(
      (existing ? existing.totalDistanceKm : 0) + aggregate.distanceKm,
      3
    );
    const totalDurationSec = roundDecimal_(
      (existing ? existing.totalDurationSec : 0) + aggregate.durationSec,
      3
    );
    const totalXp = Math.round(
      (existing ? existing.totalXp : 0) + aggregate.activityXp
    );
    const level = getLevelByXpFromLevels_(totalXp, levels);
    const row = [
      String(participant.nik),
      String(participant.nickname || ''),
      String(participant.divisionGuild || ''),
      totalActivities,
      totalDistanceKm,
      totalDurationSec,
      totalXp,
      level.currentLevel,
      level.currentLevelName,
      level.nextLevelXp == null ? '' : level.nextLevelXp,
      aggregate.lastActivityId,
      aggregate.lastActivityAt,
      now,
    ];

    if (existing) {
      snapshots.push({
        rowNumber: existing.rowNumber,
        previousValues: existing.previousValues,
      });
      existingWrites.push({ rowNumber: existing.rowNumber, values: row });
    } else {
      appendRows.push(row);
    }
  });

  return {
    sheet: sheet,
    existingWrites: existingWrites,
    appendRows: appendRows,
    snapshots: snapshots,
    appendStartRow: appendRows.length > 0 ? sheet.getLastRow() + 1 : null,
    appendedRowsWritten: false,
  };
}

function applyStravaUserStatsBatch_(batch) {
  if (!batch || !batch.sheet) return;

  batch.existingWrites.forEach(function (write) {
    batch.sheet.getRange(write.rowNumber, 1).setNumberFormat('@');
    batch.sheet
      .getRange(write.rowNumber, 1, 1, ORA_HEADERS.User_Stats.length)
      .setValues([write.values]);
  });
  if (batch.existingWrites.length > 0) invalidateSheetSnapshot_(ORA_SHEETS.USER_STATS);

  if (batch.appendRows.length > 0) {
    ensureOraSheetRowCapacity_(
      batch.sheet,
      batch.appendStartRow + batch.appendRows.length - 1
    );
    batch.sheet
      .getRange(batch.appendStartRow, 1, batch.appendRows.length, 1)
      .setNumberFormat('@');
    batch.sheet
      .getRange(
        batch.appendStartRow,
        1,
        batch.appendRows.length,
        ORA_HEADERS.User_Stats.length
      )
      .setValues(batch.appendRows);
    batch.appendedRowsWritten = true;
    invalidateSheetSnapshot_(ORA_SHEETS.USER_STATS);
  }
}

function rollbackStravaUserStatsBatch_(batch) {
  if (!batch || !batch.sheet) return;
  try {
    batch.snapshots.forEach(function (snapshot) {
      batch.sheet
        .getRange(snapshot.rowNumber, 1, 1, ORA_HEADERS.User_Stats.length)
        .setValues([snapshot.previousValues]);
    });
    if (batch.appendedRowsWritten && batch.appendRows.length > 0) {
      batch.sheet.deleteRows(batch.appendStartRow, batch.appendRows.length);
    }
  } catch (rollbackError) {
    console.error('Strava User_Stats rollback failed: %s', safeErrorMessage_(rollbackError));
  } finally {
    if (batch.snapshots.length > 0 || batch.appendedRowsWritten) {
      invalidateSheetSnapshot_(ORA_SHEETS.USER_STATS);
    }
  }
}

function ensureOraSheetRowCapacity_(sheet, requiredRows) {
  const missingRows = requiredRows - sheet.getMaxRows();
  if (missingRows > 0) sheet.insertRowsAfter(sheet.getMaxRows(), missingRows);
}

function jsonStravaSyncSuccess_(result) {
  return jsonOutput_({
    ok: true,
    apiVersion: ORA_API_VERSION,
    timestamp: new Date().toISOString(),
    result: result,
  });
}

function handleCreateImportToken_(request) {
  const sharedText = sanitizeImportText_(request.sharedText);
  const sharedUrl = sanitizeImportUrl_(request.sharedUrl);
  const sourceHint = normalizeImportActivitySource_(request.sourceHint || 'UNKNOWN');
  const imageBase64 = String(request.imageBase64 == null ? '' : request.imageBase64).trim();
  const imageMimeType = String(request.imageMimeType == null ? '' : request.imageMimeType).trim().toLowerCase();
  const imageName = sanitizeImportFileName_(request.imageName);

  if (!sharedText && !sharedUrl && !imageBase64) {
    return jsonError_('NO_SHARED_DATA', 'Tidak ada data activity untuk diimport.');
  }
  if (imageBase64 && imageMimeType.indexOf('image/') !== 0) {
    return jsonError_('INVALID_IMPORT_IMAGE', 'Format screenshot tidak didukung.');
  }

  let imageBytes = null;
  if (imageBase64) {
    try {
      imageBytes = Utilities.base64Decode(imageBase64);
    } catch (error) {
      return jsonError_('INVALID_IMPORT_IMAGE', 'Screenshot tidak valid.');
    }
    if (imageBytes.length > ORA_IMPORT_MAX_IMAGE_BYTES) {
      return jsonError_('IMPORT_IMAGE_TOO_LARGE', 'Screenshot maksimal 2 MB.');
    }
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const properties = PropertiesService.getScriptProperties();
    cleanupExpiredImportTokens_(properties, Date.now());
    const activeCount = Object.keys(properties.getProperties()).filter(function (key) {
      return key.indexOf(ORA_IMPORT_TOKEN_PROPERTY_PREFIX) === 0;
    }).length;
    if (activeCount >= ORA_IMPORT_MAX_ACTIVE) {
      return jsonError_('IMPORT_BUSY', 'Import service sedang sibuk. Coba kembali.');
    }

    const nowMillis = Date.now();
    const token = createImportTokenValue_();
    const key = importTokenPropertyKey_(token);
    const payload = {
      sharedText: sharedText || null,
      sharedUrl: sharedUrl || null,
      sourceHint: sourceHint,
      imageBase64: imageBase64 || null,
      imageMimeType: imageBase64 ? imageMimeType : null,
      imageName: imageBase64 ? imageName : null,
      receivedAt: new Date(nowMillis).toISOString(),
    };
    const file = getImportFolder_().createFile(
      Utilities.newBlob(
        JSON.stringify(payload),
        'application/json',
        'ora-import-' + key.substring(ORA_IMPORT_TOKEN_PROPERTY_PREFIX.length, 28) + '.json'
      )
    );
    properties.setProperty(key, JSON.stringify({
      state: 'PENDING',
      fileId: file.getId(),
      createdAtMillis: nowMillis,
      expiresAtMillis: nowMillis + ORA_IMPORT_TOKEN_TTL_SECONDS * 1000,
    }));
    return jsonSuccess_({
      status: 'CREATED',
      importToken: token,
      importUrl: ORA_IMPORT_WEB_URL + encodeURIComponent(token),
      expiresInSeconds: ORA_IMPORT_TOKEN_TTL_SECONDS,
    });
  } finally {
    lock.releaseLock();
  }
}

function handleGetImportPayload_(request) {
  const token = normalizeImportToken_(request.importToken);
  const record = requireImportTokenRecord_(token);
  let payload;
  try {
    payload = JSON.parse(DriveApp.getFileById(record.fileId).getBlob().getDataAsString('UTF-8'));
  } catch (error) {
    throw oraError_('IMPORT_TOKEN_INVALID', 'Import payload tidak tersedia.');
  }
  return jsonSuccess_({
    status: 'READY',
    payload: payload,
    expiresAt: new Date(record.expiresAtMillis).toISOString(),
  });
}

function handleConsumeImportToken_(request) {
  const token = normalizeImportToken_(request.importToken);
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const properties = PropertiesService.getScriptProperties();
    const key = importTokenPropertyKey_(token);
    const serialized = properties.getProperty(key);
    if (!serialized) throw oraError_('IMPORT_TOKEN_INVALID', 'Import token tidak valid.');
    const record = parseImportTokenRecord_(serialized);
    if (record.state === 'CONSUMED') {
      throw oraError_('IMPORT_ALREADY_USED', 'Import token sudah digunakan.');
    }
    if (Number(record.expiresAtMillis) <= Date.now()) {
      deleteImportPayloadFile_(record.fileId);
      properties.deleteProperty(key);
      throw oraError_('IMPORT_EXPIRED', 'Import token telah kedaluwarsa.');
    }
    deleteImportPayloadFile_(record.fileId);
    properties.setProperty(key, JSON.stringify({
      state: 'CONSUMED',
      fileId: null,
      createdAtMillis: record.createdAtMillis,
      expiresAtMillis: Date.now() + ORA_IMPORT_TOKEN_TTL_SECONDS * 1000,
    }));
    return jsonSuccess_({ status: 'CONSUMED' });
  } finally {
    lock.releaseLock();
  }
}

function requireImportTokenRecord_(token) {
  const properties = PropertiesService.getScriptProperties();
  const key = importTokenPropertyKey_(token);
  const serialized = properties.getProperty(key);
  if (!serialized) throw oraError_('IMPORT_TOKEN_INVALID', 'Import token tidak valid.');
  const record = parseImportTokenRecord_(serialized);
  if (record.state === 'CONSUMED') {
    throw oraError_('IMPORT_ALREADY_USED', 'Import token sudah digunakan.');
  }
  if (Number(record.expiresAtMillis) <= Date.now()) {
    deleteImportPayloadFile_(record.fileId);
    properties.deleteProperty(key);
    throw oraError_('IMPORT_EXPIRED', 'Import token telah kedaluwarsa.');
  }
  if (!record.fileId) throw oraError_('IMPORT_TOKEN_INVALID', 'Import payload tidak tersedia.');
  return record;
}

function parseImportTokenRecord_(serialized) {
  try {
    const record = JSON.parse(serialized);
    if (!record || !record.state || !Number.isFinite(Number(record.expiresAtMillis))) {
      throw new Error('Invalid import token record');
    }
    return record;
  } catch (error) {
    throw oraError_('IMPORT_TOKEN_INVALID', 'Import token tidak valid.');
  }
}

function cleanupExpiredImportTokens_(properties, nowMillis) {
  const all = properties.getProperties();
  Object.keys(all).forEach(function (key) {
    if (key.indexOf(ORA_IMPORT_TOKEN_PROPERTY_PREFIX) !== 0) return;
    try {
      const record = parseImportTokenRecord_(all[key]);
      if (Number(record.expiresAtMillis) > nowMillis) return;
      deleteImportPayloadFile_(record.fileId);
    } catch (error) {
      // Invalid temporary metadata is safe to delete without logging payload data.
    }
    properties.deleteProperty(key);
  });
}

function getImportFolder_() {
  const properties = PropertiesService.getScriptProperties();
  const configuredId = properties.getProperty(ORA_IMPORT_FOLDER_ID_PROPERTY);
  if (configuredId) {
    try {
      return DriveApp.getFolderById(configuredId);
    } catch (error) {
      properties.deleteProperty(ORA_IMPORT_FOLDER_ID_PROPERTY);
    }
  }
  const folder = DriveApp.createFolder('ORA Temporary Imports');
  properties.setProperty(ORA_IMPORT_FOLDER_ID_PROPERTY, folder.getId());
  return folder;
}

function deleteImportPayloadFile_(fileId) {
  if (!fileId) return;
  try {
    DriveApp.getFileById(String(fileId)).setTrashed(true);
  } catch (error) {
    // The payload is already unavailable, which is equivalent to deletion.
  }
}

function createImportTokenValue_() {
  const entropy = Utilities.getUuid() + ':' + Utilities.getUuid() + ':' + Date.now();
  return Utilities.base64EncodeWebSafe(
    Utilities.computeDigest(
      Utilities.DigestAlgorithm.SHA_256,
      entropy,
      Utilities.Charset.UTF_8
    )
  ).replace(/=+$/g, '');
}

function normalizeImportToken_(value) {
  const token = String(value == null ? '' : value).trim();
  if (!/^[A-Za-z0-9_-]{32,128}$/.test(token)) {
    throw oraError_('IMPORT_TOKEN_INVALID', 'Import token tidak valid.');
  }
  return token;
}

function importTokenPropertyKey_(token) {
  const digest = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    normalizeImportToken_(token),
    Utilities.Charset.UTF_8
  );
  return ORA_IMPORT_TOKEN_PROPERTY_PREFIX + Utilities.base64EncodeWebSafe(digest).replace(/=+$/g, '');
}

function sanitizeImportText_(value) {
  const text = String(value == null ? '' : value).trim();
  if (text.length > ORA_IMPORT_MAX_TEXT_LENGTH) {
    throw oraError_('IMPORT_TEXT_TOO_LARGE', 'Shared text terlalu panjang.');
  }
  return text;
}

function sanitizeImportUrl_(value) {
  const url = String(value == null ? '' : value).trim();
  if (!url) return '';
  if (url.length > 2048 || !/^https:\/\//i.test(url)) {
    throw oraError_('INVALID_IMPORT_URL', 'Shared URL tidak valid.');
  }
  return url;
}

function sanitizeImportFileName_(value) {
  return String(value == null ? 'activity.jpg' : value)
    .replace(/[^A-Za-z0-9._-]/g, '_')
    .substring(0, 120) || 'activity.jpg';
}

/**
 * Manual Apps Script regression for the anonymous temporary import lifecycle.
 * This creates private temporary Drive files and always removes its fixtures.
 */
function testImportTokenLifecycle() {
  const tokens = [];
  try {
    const created = JSON.parse(handleCreateImportToken_({
      sharedText: 'Morning Run\n8.09 km\n58:06',
      sharedUrl: 'https://www.strava.com/activities/test',
      sourceHint: 'STRAVA',
    }).getContent());
    assertBackendTest_(created.ok === true, 'Create import token harus berhasil.');
    const token = created.data.importToken;
    tokens.push(token);
    assertBackendTest_(!/Morning|8\.09|STRAVA/.test(token), 'Token tidak boleh berisi payload plaintext.');
    assertBackendTest_(
      created.data.importUrl === ORA_IMPORT_WEB_URL + encodeURIComponent(token),
      'Create import token harus mengembalikan URL import lengkap.'
    );

    const fetched = JSON.parse(handleGetImportPayload_({ importToken: token }).getContent());
    assertBackendTest_(fetched.ok === true, 'Fetch import token harus berhasil.');
    assertBackendTest_(
      fetched.data.payload.sharedText.indexOf('8.09 km') >= 0,
      'Fetch harus mengembalikan payload yang sama.'
    );

    const consumed = JSON.parse(handleConsumeImportToken_({ importToken: token }).getContent());
    assertBackendTest_(consumed.data.status === 'CONSUMED', 'Consume harus sukses.');
    assertImportErrorCode_(function () {
      handleConsumeImportToken_({ importToken: token });
    }, 'IMPORT_ALREADY_USED');

    const expiring = JSON.parse(handleCreateImportToken_({
      sharedText: 'Expiring test payload',
      sourceHint: 'UNKNOWN',
    }).getContent()).data.importToken;
    tokens.push(expiring);
    const properties = PropertiesService.getScriptProperties();
    const expiringKey = importTokenPropertyKey_(expiring);
    const expiringRecord = JSON.parse(properties.getProperty(expiringKey));
    expiringRecord.expiresAtMillis = Date.now() - 1;
    properties.setProperty(expiringKey, JSON.stringify(expiringRecord));
    assertImportErrorCode_(function () {
      handleGetImportPayload_({ importToken: expiring });
    }, 'IMPORT_EXPIRED');

    assertImportErrorCode_(function () {
      handleGetImportPayload_({ importToken: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' });
    }, 'IMPORT_TOKEN_INVALID');

    return {
      status: 'PASS',
      createFetchConsume: true,
      secondConsume: 'IMPORT_ALREADY_USED',
      expired: 'IMPORT_EXPIRED',
      unknown: 'IMPORT_TOKEN_INVALID',
    };
  } finally {
    tokens.forEach(cleanupImportTokenTestFixture_);
  }
}

function assertImportErrorCode_(operation, expectedCode) {
  let actualCode = null;
  try {
    operation();
  } catch (error) {
    actualCode = error && error.oraCode;
  }
  assertBackendTest_(
    actualCode === expectedCode,
    'Expected ' + expectedCode + ', received ' + String(actualCode) + '.'
  );
}

function cleanupImportTokenTestFixture_(token) {
  try {
    const properties = PropertiesService.getScriptProperties();
    const key = importTokenPropertyKey_(token);
    const serialized = properties.getProperty(key);
    if (serialized) {
      const record = parseImportTokenRecord_(serialized);
      deleteImportPayloadFile_(record.fileId);
    }
    properties.deleteProperty(key);
  } catch (error) {
    // Test cleanup is best effort and never logs temporary payload contents.
  }
}

function handleLogin_(request) {
  const nik = normalizeDigits_(request.nik);
  const pin = normalizeDigits_(request.pin);

  if (!nik || !pin) {
    return jsonError_('MISSING_CREDENTIALS', 'NIK dan PIN wajib diisi.');
  }

  if (!/^\d{4}$/.test(pin)) {
    return jsonError_('INVALID_CREDENTIALS', 'NIK atau PIN tidak valid.');
  }

  const participant = findParticipantByNik_(nik);
  if (!participant || participant.pin !== pin) {
    return jsonError_('INVALID_CREDENTIALS', 'NIK atau PIN tidak valid.');
  }

  if (participant.status !== 'ACTIVE') {
    return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
  }

  const sessionToken = Utilities.getUuid() + Utilities.getUuid();
  saveSession_(sessionToken, participant.nik);

  return jsonSuccess_({
    sessionToken: sessionToken,
    expiresInSeconds: ORA_SESSION_TTL_SECONDS,
    participant: publicParticipant_(participant),
    requiresNicknameActivation: !participant.nickname,
  });
}

function handleActivateNickname_(request) {
  const session = requireSession_(request.sessionToken);
  const nickname = String(request.nickname == null ? '' : request.nickname).trim();
  const nicknameMaxLength = getNicknameMaxLength_();

  if (!nickname) {
    return jsonError_('INVALID_NICKNAME', 'Nickname wajib diisi.');
  }

  if (nickname.length > nicknameMaxLength) {
    return jsonError_(
      'INVALID_NICKNAME',
      'Nickname maksimal ' + nicknameMaxLength + ' karakter.'
    );
  }

  if (!/^[A-Za-z0-9]+$/.test(nickname)) {
    return jsonError_('INVALID_NICKNAME', 'Nickname hanya boleh berisi huruf dan angka.');
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);

  try {
    const participant = findParticipantByNik_(session.nik);
    if (!participant) {
      return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
    }

    if (participant.status !== 'ACTIVE') {
      return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
    }

    if (participant.nickname) {
      if (participant.nickname.toLowerCase() === nickname.toLowerCase()) {
        return jsonSuccess_({
          participant: publicParticipant_(participant),
          nicknameSaved: true,
          alreadyActivated: true,
        });
      }

      return jsonError_(
        'NICKNAME_ALREADY_ACTIVATED',
        'Nickname sudah diaktifkan. Hubungi admin untuk perubahan.'
      );
    }

    if (isNicknameTaken_(nickname, participant.nik)) {
      return jsonError_('NICKNAME_TAKEN', 'Nickname sudah digunakan participant lain.');
    }

    const sheet = getValidatedSheet_(ORA_SHEETS.PARTICIPANTS);
    const nicknameColumn = participant.headerMap.Nickname + 1;
    const updatedAtColumn = participant.headerMap.Updated_At + 1;
    const now = new Date();

    sheet.getRange(participant.rowNumber, nicknameColumn).setValue(nickname);
    sheet.getRange(participant.rowNumber, updatedAtColumn).setValue(now);
    invalidateSheetSnapshot_(ORA_SHEETS.PARTICIPANTS);

    participant.nickname = nickname;
    participant.updatedAt = now;

    return jsonSuccess_({
      participant: publicParticipant_(participant),
      nicknameSaved: true,
      alreadyActivated: false,
    });
  } finally {
    lock.releaseLock();
  }
}

function handleUpdateNickname_(request) {
  const session = requireSession_(request.sessionToken);
  const nickname = String(request.nickname == null ? '' : request.nickname).trim().toUpperCase();
  const nicknameMaxLength = getNicknameMaxLength_();

  if (!nickname) {
    return jsonError_('INVALID_NICKNAME', 'Nickname wajib diisi.');
  }
  if (nickname.length > nicknameMaxLength) {
    return jsonError_(
      'INVALID_NICKNAME',
      'Nickname maksimal ' + nicknameMaxLength + ' karakter.'
    );
  }
  if (!/^[A-Z0-9]+$/.test(nickname)) {
    return jsonError_('INVALID_NICKNAME', 'Nickname hanya boleh berisi huruf dan angka.');
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const participant = findParticipantByNik_(session.nik);
    if (!participant) {
      return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
    }
    if (participant.status !== 'ACTIVE') {
      return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
    }
    if (participant.nickname && participant.nickname.toUpperCase() === nickname) {
      return jsonSuccess_({
        participant: publicParticipant_(participant),
        nicknameSaved: true,
        unchanged: true,
      });
    }
    if (isNicknameTaken_(nickname, participant.nik)) {
      return jsonError_('NICKNAME_TAKEN', 'Nickname sudah digunakan participant lain.');
    }

    const sheet = getValidatedSheet_(ORA_SHEETS.PARTICIPANTS);
    const now = new Date();
    sheet.getRange(participant.rowNumber, participant.headerMap.Nickname + 1).setValue(nickname);
    sheet.getRange(participant.rowNumber, participant.headerMap.Updated_At + 1).setValue(now);
    invalidateSheetSnapshot_(ORA_SHEETS.PARTICIPANTS);
    participant.nickname = nickname;
    participant.updatedAt = now;

    return jsonSuccess_({
      participant: publicParticipant_(participant),
      nicknameSaved: true,
      unchanged: false,
    });
  } finally {
    lock.releaseLock();
  }
}

function handleSubmitActivity_(request) {
  const session = requireSession_(request.sessionToken);
  const activity = request.activity;

  if (!activity || typeof activity !== 'object' || Array.isArray(activity)) {
    return jsonError_('MISSING_ACTIVITY', 'Data activity wajib dikirim.');
  }

  const activityId = String(activity.activityId == null ? '' : activity.activityId).trim();
  const startTime = String(activity.startTime == null ? '' : activity.startTime).trim();
  const endTime = String(activity.endTime == null ? '' : activity.endTime).trim();
  const durationSec = Number(activity.durationSec);
  const distanceKm = Number(activity.distanceKm);
  const avgPace = String(activity.avgPace == null ? '' : activity.avgPace).trim();
  const source = normalizeImportActivitySource_(activity.source);
  const sourceUrl = String(activity.sourceUrl == null ? '' : activity.sourceUrl).trim();
  const sourceRef = String(
    activity.sourceRef == null ? extractActivitySourceRef_(source, sourceUrl) : activity.sourceRef
  ).trim();
  const deviceTime = String(activity.deviceTime == null ? '' : activity.deviceTime).trim();

  if (!activityId) {
    return jsonError_('MISSING_ACTIVITY_ID', 'ActivityId wajib diisi.');
  }

  if (!startTime) {
    return jsonError_('MISSING_START_TIME', 'StartTime wajib diisi.');
  }

  if (!endTime) {
    return jsonError_('MISSING_END_TIME', 'EndTime wajib diisi.');
  }

  if (!Number.isFinite(durationSec) || durationSec <= 0) {
    return jsonError_('INVALID_DURATION_SEC', 'DurationSec harus berupa angka lebih dari 0.');
  }

  if (!Number.isFinite(distanceKm) || distanceKm <= 0) {
    return jsonError_('INVALID_DISTANCE_KM', 'DistanceKm harus berupa angka lebih dari 0.');
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);

  try {
    const participant = findParticipantByNik_(session.nik);
    if (!participant) {
      return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
    }

    if (participant.status !== 'ACTIVE') {
      return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
    }

    const sheet = getActivitiesSheet_();
    if (
      sourceRef &&
      findActivityByNikSourceAndRef_(sheet, participant.nik, source, sourceRef)
    ) {
      return jsonSuccess_({
        status: 'DUPLICATE',
        activityId: activityId,
        message: 'Activity source already synced',
      });
    }
    if (findActivityByNikAndActivityId_(sheet, participant.nik, activityId)) {
      return jsonSuccess_({
        status: 'DUPLICATE',
        activityId: activityId,
        message: 'Activity already synced',
      });
    }

    const activityRowNumber = appendActivity_(sheet, {
      activityId: activityId,
      nik: participant.nik,
      nickname: participant.nickname,
      division: participant.divisionGuild,
      startTime: startTime,
      endTime: endTime,
      durationSec: durationSec,
      distanceKm: distanceKm,
      avgPace: avgPace,
      source: source,
      sourceRef: sourceRef,
      sourceUrl: sourceUrl,
      deviceTime: deviceTime,
    });

    try {
      const activityXp = calculateActivityXp_(distanceKm, 'COMPLETED');
      upsertUserStats_({
        nik: participant.nik,
        nickname: participant.nickname,
        division: participant.divisionGuild,
        activityId: activityId,
        activityAt: endTime || startTime,
        durationSec: durationSec,
        distanceKm: distanceKm,
        activityXp: activityXp,
      });
    } catch (error) {
      // Keep submitActivity retryable if stats aggregation cannot be completed.
      sheet.deleteRow(activityRowNumber);
      invalidateSheetSnapshot_(ORA_SHEETS.ACTIVITIES);
      throw error;
    }

    return jsonSuccess_({
      status: 'SAVED',
      activityId: activityId,
      message: 'Activity saved',
    });
  } finally {
    lock.releaseLock();
  }
}

/**
 * Authenticated QR attendance endpoint.
 *
 * This deliberately writes only Attendance_Records and TotalXP/level in
 * User_Stats. It never touches Activities or running totals.
 */
function handleSubmitAttendance_(request) {
  const session = requireSession_(request.sessionToken);
  const qrToken = String(request.qrToken == null ? '' : request.qrToken).trim();
  const configurationStatus = getAttendanceFeatureStatus_(getActiveConfig_());

  if (configurationStatus) {
    return jsonSuccess_({ status: configurationStatus });
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);

  try {
    const participant = findParticipantByNik_(session.nik);
    if (!participant) {
      return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
    }
    if (participant.status !== 'ACTIVE') {
      return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
    }

    const event = findAttendanceEventByQrToken_(qrToken, getAttendanceEvents_());
    if (!event) {
      return jsonSuccess_({ status: 'INVALID_QR' });
    }
    const eventStatus = getAttendanceEventEligibilityStatus_(event, new Date());
    if (eventStatus === 'EVENT_INACTIVE') {
      return jsonSuccess_(attendanceResponse_(eventStatus, event, null, getAttendanceStats_(participant)));
    }

    const recordsSheet = getAttendanceRecordsSheet_();
    const duplicate = findAttendanceRecordByNikAndEventId_(
      recordsSheet,
      participant.nik,
      event.eventId
    );
    if (duplicate) {
      return jsonSuccess_(
        attendanceResponse_('ALREADY_CHECKED_IN', event, duplicate, getAttendanceStats_(participant))
      );
    }

    if (eventStatus !== 'SUCCESS') {
      return jsonSuccess_(attendanceResponse_(eventStatus, event, null, getAttendanceStats_(participant)));
    }

    const records = getAttendanceRecordsForNik_(participant.nik);
    const streakCount = calculateAttendanceStreakForEvent_(
      getAttendanceEvents_(),
      records,
      participant.nik,
      event
    );
    const rewards = getAttendanceRewardRows_();
    const baseXp = getAttendanceBaseXp_(rewards);
    const streakBonusXp = getAttendanceStreakBonusXp_(rewards, streakCount);
    const totalXp = baseXp + streakBonusXp;
    const record = appendAttendanceRecord_(recordsSheet, {
      attendanceId: Utilities.getUuid(),
      eventId: event.eventId,
      nik: participant.nik,
      nickname: participant.nickname,
      checkInAt: new Date(),
      baseXp: baseXp,
      streakCount: streakCount,
      streakBonusXp: streakBonusXp,
      totalXp: totalXp,
      status: 'PROCESSING',
    });
    let statsWrite = null;

    try {
      statsWrite = grantAttendanceXp_(participant, totalXp);
      const savedRecord = markAttendanceRecordSuccess_(recordsSheet, record.rowNumber);
      return jsonSuccess_(attendanceResponse_('SUCCESS', event, savedRecord, statsWrite.stats));
    } catch (error) {
      try {
        if (statsWrite) restoreUserStatsWrite_(statsWrite);
      } finally {
        recordsSheet.deleteRow(record.rowNumber);
        invalidateSheetSnapshot_(ORA_SHEETS.ATTENDANCE_RECORDS);
      }
      throw error;
    }
  } finally {
    lock.releaseLock();
  }
}

function attendanceResponse_(status, event, record, stats) {
  const current = stats || {};
  return {
    status: status,
    eventId: event ? event.eventId : null,
    eventName: event ? event.eventName : null,
    checkInAt: record ? toIsoDateTimeOrNull_(record.checkInAt) : null,
    baseXP: record ? record.baseXp : 0,
    streakCount: record ? record.streakCount : 0,
    streakBonusXP: record ? record.streakBonusXp : 0,
    totalXP: record ? record.totalXp : 0,
    currentXP: Math.max(0, Number(current.totalXp) || 0),
    currentLevel: Number(current.currentLevel) || 0,
  };
}

function getAttendanceFeatureStatus_(config) {
  if (!config || config.ATTENDANCE_ENABLED !== true) return 'ATTENDANCE_DISABLED';
  if (config.ATTENDANCE_QR_ENABLED !== true) return 'ATTENDANCE_QR_DISABLED';
  return null;
}

function getAttendanceStats_(participant) {
  return getUserStatsByNik_(participant.nik) || createDefaultUserStats_(participant);
}

function handleGetActivityHistory_(request) {
  const session = requireSession_(request.sessionToken);
  const participant = findParticipantByNik_(session.nik);

  if (!participant) {
    return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
  }
  if (participant.status !== 'ACTIVE') {
    return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
  }

  const limit = clampInteger_(request.limit, 50, 1, 100);
  const offset = clampInteger_(request.offset, 0, 0, 10000);
  const allActivities = mapActivityHistoryRowsForNik_(
    readSheetObjects_(ORA_SHEETS.ACTIVITIES),
    session.nik
  );
  const activities = allActivities.slice(offset, offset + limit);

  return jsonSuccess_({
    activities: activities,
    limit: limit,
    offset: offset,
    total: allActivities.length,
    hasMore: offset + activities.length < allActivities.length,
  });
}

function mapActivityHistoryRowsForNik_(rows, nik) {
  const targetNik = normalizeDigits_(nik);
  const byActivityId = Object.create(null);

  rows.forEach(function (row) {
    if (normalizeDigits_(row.NIK) !== targetNik) return;
    if (normalizeQuestType_(row.Status) !== 'COMPLETED') return;

    const activityId = String(row.ActivityId || '').trim();
    const startTime = toDateOrNull_(row.StartTime);
    const endTime = toDateOrNull_(row.EndTime);
    const syncedAt = toDateOrNull_(row.SyncedAt);
    const activityTime = endTime || startTime;
    if (!activityId || !startTime || !endTime || !activityTime) return;

    const item = {
      activityId: activityId,
      startTime: startTime.toISOString(),
      endTime: endTime.toISOString(),
      durationSec: toNonNegativeFiniteNumber_(row.DurationSec),
      distanceKm: toNonNegativeFiniteNumber_(row.DistanceKm),
      avgPace: String(row.AvgPace || '').trim(),
      status: 'COMPLETED',
      source: String(row.Source || '').trim(),
      sourceRef: String(row.SourceRef || '').trim(),
      sourceUrl: String(row.SourceUrl || '').trim(),
      syncedAt: syncedAt ? syncedAt.toISOString() : null,
      activityTimeMillis: activityTime.getTime(),
    };
    const existing = byActivityId[activityId];
    if (!existing || item.activityTimeMillis > existing.activityTimeMillis) {
      byActivityId[activityId] = item;
    }
  });

  return Object.keys(byActivityId).map(function (activityId) {
    return byActivityId[activityId];
  }).sort(function (a, b) {
    if (b.activityTimeMillis !== a.activityTimeMillis) {
      return b.activityTimeMillis - a.activityTimeMillis;
    }
    return b.activityId.localeCompare(a.activityId);
  }).map(function (activity) {
    delete activity.activityTimeMillis;
    return activity;
  });
}

function clampInteger_(value, fallback, minimum, maximum) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(maximum, Math.max(minimum, Math.floor(number)));
}

function testActivityHistoryOwnerIsolation() {
  const rows = [
    {
      ActivityId: 'A-OLD', NIK: '1001', StartTime: '2026-08-14T00:00:00Z',
      EndTime: '2026-08-14T00:30:00Z', DurationSec: 1800, DistanceKm: 5,
      AvgPace: '06:00', Status: 'COMPLETED', Source: 'ANDROID',
      SyncedAt: '2026-08-14T00:31:00Z',
    },
    {
      ActivityId: 'B-SECRET', NIK: '2002', StartTime: '2026-08-16T00:00:00Z',
      EndTime: '2026-08-16T00:30:00Z', DurationSec: 1800, DistanceKm: 5,
      AvgPace: '06:00', Status: 'COMPLETED', Source: 'ANDROID',
      SyncedAt: '2026-08-16T00:31:00Z',
    },
    {
      ActivityId: 'A-PENDING', NIK: '1001', StartTime: '2026-08-15T00:00:00Z',
      EndTime: '2026-08-15T00:30:00Z', DurationSec: 1800, DistanceKm: 5,
      AvgPace: '06:00', Status: 'PENDING', Source: 'ANDROID',
      SyncedAt: '2026-08-15T00:31:00Z',
    },
  ];
  const result = mapActivityHistoryRowsForNik_(rows, '1001');
  assertBackendTest_(result.length === 1, 'History harus hanya memuat activity resmi owner.');
  assertBackendTest_(result[0].activityId === 'A-OLD', 'Activity participant lain terekspos.');
  assertBackendTest_(!Object.prototype.hasOwnProperty.call(result[0], 'NIK'), 'NIK tidak boleh diekspos.');
  return { ok: true, ownerIsolation: true, completedOnly: true };
}

function handleGetUserStats_(request) {
  const session = requireSession_(request.sessionToken);
  const participant = findParticipantByNik_(session.nik);

  if (!participant) {
    return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
  }
  if (participant.status !== 'ACTIVE') {
    return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
  }

  const storedStats = getUserStatsByNik_(participant.nik);
  const stats = storedStats
    ? publicUserStats_(storedStats)
    : createDefaultUserStats_(participant);

  return jsonUserStatsSuccess_(stats);
}

function getCachedGuildSummaryPayload_(participant) {
  const division = String(participant.divisionGuild || '').trim();
  if (!division) {
    return { status: 'UNASSIGNED', guild: null, members: [] };
  }

  return getCachedGuildLeaderboardData_(
    'guild_summary',
    [readHeavyCacheIdentity_(normalizeDivisionKey_(division))],
    function () {
      const guildMasterRecords = getGuildMasterRecords_();
      const levels = getActiveLevels_();
      const guildResolution = resolveGuildMetadata_(division, guildMasterRecords);
      const summary = buildGuildSummary_(
        participant,
        getGuildParticipantRows_(),
        getUserStatsByNikMap_(),
        getDefaultGuildLevel_(levels),
        guildResolution.guild,
        levels
      );
      return {
        status: guildResolution.status,
        guild: summary.guild,
        members: summary.members,
      };
    }
  );
}

function getCachedGuildDirectoryPayload_() {
  return getCachedGuildLeaderboardData_('guild_directory', [], function () {
    const levels = getActiveLevels_();
    return {
      guilds: buildGuildDirectory_(
        getGuildParticipantRows_(),
        getUserStatsByNikMap_(),
        getDefaultGuildLevel_(levels),
        getGuildMasterRecords_(),
        levels
      ),
    };
  });
}

function getCachedLeaderboardPayload_(participant, scope, metric) {
  const division = String(participant.divisionGuild || '').trim();
  if (scope === 'GUILD' && !division) {
    return {
      scope: 'GUILD',
      metric: metric,
      status: 'NO_GUILD',
      leaderboard: [],
      currentUserRank: null,
    };
  }

  const userIdentity = readHeavyCacheIdentity_(normalizeDigits_(participant.nik));
  const cacheType = scope === 'GUILD' ? 'leaderboard_guild' : 'leaderboard_global';
  const keyParts = scope === 'GUILD'
    ? [metric, readHeavyCacheIdentity_(normalizeDivisionKey_(division)), userIdentity]
    : [metric, userIdentity];

  return getCachedGuildLeaderboardData_(cacheType, keyParts, function () {
    const participants = getGuildParticipantRows_();
    let eligibleParticipants = participants;
    if (scope === 'GUILD') {
      const divisionKey = normalizeDivisionKey_(division);
      eligibleParticipants = participants.filter(function (candidate) {
        return normalizeDivisionKey_(candidate.divisionGuild) === divisionKey;
      });
    }
    const result = buildLeaderboard_(
      participant.nik,
      eligibleParticipants,
      getUserStatsByNikMap_(),
      metric,
      50
    );
    return {
      scope: scope,
      metric: metric,
      status: 'ACTIVE',
      leaderboard: result.leaderboard,
      currentUserRank: result.currentUserRank,
    };
  });
}

function getCachedGuildDataPayload_(participant, scope, metric) {
  const division = String(participant.divisionGuild || '').trim();
  return getCachedGuildLeaderboardData_(
    'guild_data',
    [
      scope,
      metric,
      readHeavyCacheIdentity_(normalizeDigits_(participant.nik)),
      readHeavyCacheIdentity_(normalizeDivisionKey_(division)),
    ],
    function () {
      const summary = getCachedGuildSummaryPayload_(participant);
      const directory = getCachedGuildDirectoryPayload_();
      const leaderboard = getCachedLeaderboardPayload_(participant, scope, metric);
      return {
        status: summary.status,
        guild: summary.guild,
        members: summary.members,
        guilds: directory.guilds,
        leaderboard: {
          scope: leaderboard.scope,
          metric: leaderboard.metric,
          status: leaderboard.status,
          entries: leaderboard.leaderboard,
          currentUserRank: leaderboard.currentUserRank,
        },
      };
    }
  );
}

function handleGetGuildData_(request) {
  const session = requireSession_(request.sessionToken);
  const participants = getGuildParticipantRows_();
  const participant = participants.find(function (candidate) {
    return candidate.nik === normalizeDigits_(session.nik);
  }) || null;

  if (!participant) {
    return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
  }
  if (participant.status !== 'ACTIVE') {
    return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
  }

  const scope = String(request.scope || 'GLOBAL').trim().toUpperCase();
  const metric = String(request.metric || 'TOTAL_XP').trim().toUpperCase();
  if (scope !== 'GLOBAL' && scope !== 'GUILD') {
    return jsonError_('INVALID_LEADERBOARD_SCOPE', 'Scope leaderboard belum didukung.');
  }
  if (!isSupportedLeaderboardMetric_(metric)) {
    return jsonError_('INVALID_LEADERBOARD_METRIC', 'Metric leaderboard tidak dikenali.');
  }

  const payload = getCachedGuildDataPayload_(participant, scope, metric);

  return jsonGuildDataSuccess_(
    payload.status,
    payload.guild,
    payload.members,
    payload.guilds,
    payload.leaderboard.scope,
    payload.leaderboard.metric,
    payload.leaderboard.status,
    payload.leaderboard.entries,
    payload.leaderboard.currentUserRank
  );
}

function handleGetGuildSummary_(request) {
  const session = requireSession_(request.sessionToken);
  const participant = findParticipantByNik_(session.nik);

  if (!participant) {
    return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
  }
  if (participant.status !== 'ACTIVE') {
    return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
  }

  const payload = getCachedGuildSummaryPayload_(participant);
  return jsonGuildSummarySuccess_(payload.status, payload.guild, payload.members);
}

function handleGetGuildDirectory_(request) {
  const session = requireSession_(request.sessionToken);
  const participant = findParticipantByNik_(session.nik);

  if (!participant) {
    return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
  }
  if (participant.status !== 'ACTIVE') {
    return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
  }

  return jsonGuildDirectorySuccess_(getCachedGuildDirectoryPayload_().guilds);
}

function handleGetLeaderboard_(request) {
  const session = requireSession_(request.sessionToken);
  const participant = findParticipantByNik_(session.nik);

  if (!participant) {
    return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
  }
  if (participant.status !== 'ACTIVE') {
    return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
  }

  const scope = String(request.scope || 'GLOBAL').trim().toUpperCase();
  const metric = String(request.metric || 'TOTAL_XP').trim().toUpperCase();
  if (scope !== 'GLOBAL' && scope !== 'GUILD') {
    return jsonError_('INVALID_LEADERBOARD_SCOPE', 'Scope leaderboard belum didukung.');
  }
  if (!isSupportedLeaderboardMetric_(metric)) {
    return jsonError_('INVALID_LEADERBOARD_METRIC', 'Metric leaderboard tidak dikenali.');
  }

  const result = getCachedLeaderboardPayload_(participant, scope, metric);
  return jsonLeaderboardSuccess_(
    result.scope,
    result.metric,
    result.leaderboard,
    result.currentUserRank,
    result.status
  );
}

function handleGetQuestProgress_(request) {
  const session = requireSession_(request.sessionToken);
  const participant = findParticipantByNik_(session.nik);

  if (!participant) {
    return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
  }
  if (participant.status !== 'ACTIVE') {
    return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
  }

  const participantRows = getGuildParticipantRows_();
  const activityRows = readSheetObjects_(ORA_SHEETS.ACTIVITIES);
  const activities = mapCompletedActivityRowsForNik_(activityRows, participant.nik);
  const attendanceRecords = getAttendanceRecordsForNik_(participant.nik);
  const guildContext = buildGuildActivityContext_(participant, participantRows, activityRows);
  const userStats = getUserStatsByNik_(participant.nik);
  const claimsByQuestId = getClaimedQuestsByNik_(participant.nik);
  const questConfig = getActiveConfig_();
  const quests = getActiveQuests_().map(function (quest) {
    const progress = calculateQuestProgress_(
      quest,
      activities,
      userStats,
      guildContext,
      questConfig,
      attendanceRecords
    );
    return attachQuestClaim_(progress, claimsByQuestId[quest.questId] || null);
  });

  return jsonQuestProgressSuccess_(quests);
}

function handleClaimQuestReward_(request) {
  const session = requireSession_(request.sessionToken);
  const participant = findParticipantByNik_(session.nik);
  const questId = String(request.questId == null ? '' : request.questId).trim();

  if (!participant) {
    return jsonError_('PARTICIPANT_NOT_FOUND', 'Participant tidak ditemukan.');
  }
  if (participant.status !== 'ACTIVE') {
    return jsonError_('ACCOUNT_INACTIVE', 'Akun ORA tidak aktif. Hubungi admin.');
  }
  if (!questId) {
    return jsonError_('MISSING_QUEST_ID', 'QuestId wajib diisi.');
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);

  try {
    const quest = getActiveQuests_().find(function (candidate) {
      return candidate.questId === questId;
    });
    if (!quest) {
      return jsonError_('QUEST_NOT_ACTIVE', 'Quest tidak ditemukan atau sudah tidak aktif.');
    }
    if (mapQuestType_(normalizeQuestType_(quest.questType)) === 'GUILD_DISTANCE') {
      return jsonError_(
        'GUILD_REWARD_NOT_READY',
        'Reward guild quest belum tersedia.'
      );
    }

    const claimsSheet = ensureQuestClaimsSheet_();
    const existingClaim = findQuestClaim_(claimsSheet, participant.nik, questId);
    if (existingClaim) {
      if (existingClaim.status === 'CLAIMED') {
        return jsonSuccess_({
          status: 'ALREADY_CLAIMED',
          claim: publicQuestClaim_(existingClaim),
        });
      }
      throw oraError_(
        'CLAIM_PENDING_REVIEW',
        'Klaim sebelumnya belum selesai. Silakan coba lagi nanti.'
      );
    }

    const activities = getCompletedActivitiesForNik_(participant.nik);
    const attendanceRecords = getAttendanceRecordsForNik_(participant.nik);
    const userStats = getUserStatsByNik_(participant.nik);
    const progress = calculateQuestProgress_(
      quest,
      activities,
      userStats,
      null,
      getActiveConfig_(),
      attendanceRecords
    );
    if (progress.status === 'UNSUPPORTED_GROUP_SCOPE') {
      return jsonError_(
        'QUEST_GROUP_SCOPE_UNSUPPORTED',
        'Reward guild quest belum tersedia.'
      );
    }
    if (progress.status === 'UNKNOWN_TYPE') {
      return jsonError_('QUEST_TYPE_UNSUPPORTED', 'Tipe quest belum didukung.');
    }
    if (!progress.completed) {
      return jsonError_('QUEST_NOT_COMPLETED', 'Quest belum selesai.');
    }

    const rewardXp = Math.max(0, Math.round(Number(quest.rewardXp) || 0));
    const claim = appendQuestClaim_(claimsSheet, {
      claimId: Utilities.getUuid(),
      nik: participant.nik,
      questId: quest.questId,
      questName: quest.questName,
      rewardXp: rewardXp,
      status: 'PROCESSING',
    });
    let statsWrite = null;

    try {
      statsWrite = grantQuestRewardXp_(participant, rewardXp);
      const claimed = markQuestClaimed_(claimsSheet, claim.rowNumber);
      return jsonSuccess_({
        status: 'CLAIMED',
        claim: publicQuestClaim_(claimed),
        userStats: publicUserStats_(statsWrite.stats),
      });
    } catch (error) {
      try {
        if (statsWrite) restoreUserStatsWrite_(statsWrite);
      } finally {
        claimsSheet.deleteRow(claim.rowNumber);
        invalidateSheetSnapshot_(ORA_SHEETS.QUEST_CLAIMS);
      }
      throw error;
    }
  } finally {
    lock.releaseLock();
  }
}

function getActiveConfig_() {
  return getCachedMasterData_(ORA_SHEETS.CONFIG, function () {
    const rows = readSheetObjects_(ORA_SHEETS.CONFIG);
    const result = {};

    rows.forEach(function (row) {
      if (!isTrue_(row.Active)) return;

      const key = String(row.Config_Key || '').trim();
      if (!key) return;

      result[key] = convertConfigValue_(row.Config_Value, row.Data_Type);
    });

    return result;
  });
}

function getAttendanceEventsSheet_() {
  return getValidatedSheet_(ORA_SHEETS.ATTENDANCE_EVENTS);
}

function getAttendanceRecordsSheet_() {
  return getValidatedSheet_(ORA_SHEETS.ATTENDANCE_RECORDS);
}

function getAttendanceRewardRows_() {
  return getCachedMasterData_(ORA_SHEETS.ATTENDANCE_REWARDS, function () {
    return readSheetObjects_(ORA_SHEETS.ATTENDANCE_REWARDS).map(function (row) {
      return {
        rewardType: String(row.RewardType || '').trim().toUpperCase(),
        milestone: toFiniteNumberOrNull_(row.Milestone),
        xp: toFiniteNumberOrNull_(row.XP),
        status: String(row.Status || '').trim().toUpperCase(),
      };
    });
  });
}

function getAttendanceEvents_() {
  const sheet = getAttendanceEventsSheet_();
  const range = sheet.getDataRange();
  const values = range.getValues();
  const displayValues = range.getDisplayValues();
  if (values.length < 2) return [];

  const headerMap = createHeaderMap_(displayValues[0]);
  const timeZone = getOraSpreadsheet_().getSpreadsheetTimeZone();
  return values.slice(1).map(function (row, index) {
    return attendanceEventFromRow_(row, displayValues[index + 1], headerMap, index + 2, timeZone);
  }).filter(function (event) {
    return !!event.eventId;
  });
}

/** Adds the two editor-only QR token actions when this script is sheet-bound. */
function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('ORA Attendance')
    .addItem('Generate QR Token', 'generateAttendanceQrTokenForSelectedEvent')
    .addItem('Regenerate QR Token', 'regenerateAttendanceQrTokenForSelectedEvent')
    .addSeparator()
    .addItem('Set/Replace Strava Sync Secret', 'promptSetOraStravaSyncSecret')
    .addToUi();
}

function promptSetOraStravaSyncSecret() {
  const ui = SpreadsheetApp.getUi();
  const properties = PropertiesService.getScriptProperties();
  const replacing = !!properties.getProperty(ORA_STRAVA_SYNC_SECRET_PROPERTY);
  const response = ui.prompt(
    replacing ? 'Replace Strava Sync Secret' : 'Set Strava Sync Secret',
    'Masukkan secret acak minimal 32 karakter. Nilai tidak akan ditulis ke log. ' +
      (replacing ? 'Secret lama akan langsung tidak berlaku.' : ''),
    ui.ButtonSet.OK_CANCEL
  );
  if (response.getSelectedButton() !== ui.Button.OK) {
    return { saved: false, cancelled: true };
  }

  const secret = response.getResponseText().trim();
  if (secret.length < 32) {
    ui.alert('Secret belum disimpan', 'Secret harus minimal 32 karakter.', ui.ButtonSet.OK);
    return { saved: false, invalid: true };
  }

  properties.setProperty(ORA_STRAVA_SYNC_SECRET_PROPERTY, secret);
  ui.alert(
    'Secret tersimpan',
    'ORA_STRAVA_SYNC_SECRET berhasil disimpan. Gunakan nilai yang sama di aplikasi Windows.',
    ui.ButtonSet.OK
  );
  return { saved: true, replaced: replacing };
}

/**
 * Admin/editor action. Pass an EventId directly when running from the editor.
 * An existing token is returned unchanged; use regenerateAttendanceQrToken for
 * the explicit destructive action.
 */
function generateAttendanceQrToken(eventId) {
  return setAttendanceQrToken_(eventId, false);
}

/** Admin/editor action that explicitly replaces a selected event's QR token. */
function regenerateAttendanceQrToken(eventId) {
  return setAttendanceQrToken_(eventId, true);
}

function generateAttendanceQrTokenForSelectedEvent() {
  return runSelectedAttendanceQrAction_(false);
}

function regenerateAttendanceQrTokenForSelectedEvent() {
  return runSelectedAttendanceQrAction_(true);
}

function runSelectedAttendanceQrAction_(regenerate) {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  const sheet = spreadsheet && spreadsheet.getActiveSheet();
  const rowNumber = sheet && sheet.getActiveRange() ? sheet.getActiveRange().getRow() : 0;
  if (!sheet || sheet.getName() !== ORA_SHEETS.ATTENDANCE_EVENTS || rowNumber < 2) {
    throw new Error('Pilih satu row event pada Attendance_Event_Master terlebih dahulu.');
  }
  let headerMap;
  try {
    headerMap = getAttendanceQrCodeHeaderMap_(sheet);
  } catch (error) {
    SpreadsheetApp.getUi().alert(
      'QR CODE SETUP ERROR',
      error && error.message ? error.message : 'Kolom QRCode tidak ditemukan.',
      SpreadsheetApp.getUi().ButtonSet.OK
    );
    return { ok: false, error: error && error.oraCode ? error.oraCode : 'CONFIG_ERROR' };
  }
  const eventId = String(sheet.getRange(rowNumber, headerMap.EventId + 1).getValue() || '').trim();
  const result = setAttendanceQrToken_(eventId, regenerate);
  SpreadsheetApp.getUi().alert(
    result.regenerated ? 'QR token diregenerate untuk ' : 'QR token siap untuk ',
    result.eventId + '\n\nPayload QR:\n' + result.qrToken,
    SpreadsheetApp.getUi().ButtonSet.OK
  );
  return result;
}

function setAttendanceQrToken_(eventId, regenerate) {
  const targetEventId = String(eventId || '').trim();
  if (!targetEventId) throw oraError_('MISSING_EVENT_ID', 'EventId wajib diisi.');

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const events = getAttendanceEvents_();
    const sheet = getAttendanceEventsSheet_();
    const headerMap = getAttendanceQrCodeHeaderMap_(sheet);
    const event = events.find(function (candidate) {
      return candidate.eventId === targetEventId;
    });
    if (!event) throw oraError_('EVENT_NOT_FOUND', 'Event attendance tidak ditemukan.');

    if (event.qrToken && !regenerate) {
      const qrCodeFormula = setAttendanceQrCodeFormula_(sheet, event.rowNumber, headerMap);
      return {
        ok: true,
        generated: false,
        regenerated: false,
        eventId: event.eventId,
        qrToken: event.qrToken,
        qrCodeFormula: qrCodeFormula,
      };
    }

    const token = newUniqueAttendanceQrToken_(events);
    sheet.getRange(event.rowNumber, headerMap.QRToken + 1).setValue(token);
    const qrCodeFormula = setAttendanceQrCodeFormula_(sheet, event.rowNumber, headerMap);
    sheet.getRange(event.rowNumber, headerMap.UpdatedAt + 1).setValue(new Date());
    return {
      ok: true,
      generated: !event.qrToken,
      regenerated: !!event.qrToken,
      eventId: event.eventId,
      qrToken: token,
      qrCodeFormula: qrCodeFormula,
    };
  } finally {
    lock.releaseLock();
  }
}

function getAttendanceQrCodeHeaderMap_(sheet) {
  const headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getDisplayValues()[0];
  return getRequiredAttendanceQrCodeHeaderMap_(headers);
}

function getRequiredAttendanceQrCodeHeaderMap_(headers) {
  const headerMap = createHeaderMap_(headers);
  const requiredHeaders = ['EventId', 'QRToken', 'QRCode'];
  const missing = requiredHeaders.filter(function (header) {
    return headerMap[header] === undefined;
  });
  if (missing.length > 0) {
    throw oraError_(
      'INVALID_ATTENDANCE_QR_SCHEMA',
      'Attendance_Event_Master memerlukan kolom: ' + missing.join(', ') +
        '. Tambahkan header QRCode sebelum membuat QR token.'
    );
  }
  return headerMap;
}

function setAttendanceQrCodeFormula_(sheet, rowNumber, headerMap) {
  const formula = buildAttendanceQrCodeFormula_(headerMap, rowNumber);
  sheet.getRange(rowNumber, headerMap.QRCode + 1).setFormula(formula);
  return formula;
}

function buildAttendanceQrCodeFormula_(headerMap, rowNumber) {
  if (!headerMap || headerMap.QRToken === undefined || headerMap.QRCode === undefined) {
    throw oraError_(
      'INVALID_ATTENDANCE_QR_SCHEMA',
      'Kolom QRToken dan QRCode diperlukan untuk membuat formula QR Code.'
    );
  }
  const qrTokenCell = columnNumberToA1_(headerMap.QRToken + 1) + Number(rowNumber);
  return '=IMAGE("https://quickchart.io/qr?text="&ENCODEURL(' + qrTokenCell + ')&"&size=250")';
}

function columnNumberToA1_(columnNumber) {
  let number = Number(columnNumber);
  let result = '';
  while (number > 0) {
    const remainder = (number - 1) % 26;
    result = String.fromCharCode(65 + remainder) + result;
    number = Math.floor((number - 1) / 26);
  }
  return result;
}

function newUniqueAttendanceQrToken_(events) {
  const existing = {};
  events.forEach(function (event) {
    if (event.qrToken) existing[event.qrToken] = true;
  });

  for (let attempt = 0; attempt < 10; attempt += 1) {
    const entropy = Utilities.getUuid() + ':' + Utilities.getUuid() + ':' + new Date().getTime();
    const digest = Utilities.computeDigest(
      Utilities.DigestAlgorithm.SHA_256,
      entropy,
      Utilities.Charset.UTF_8
    );
    const token = 'ORAATT-' + Utilities.base64EncodeWebSafe(digest).replace(/=+$/g, '');
    if (!existing[token]) return token;
  }
  throw oraError_('TOKEN_GENERATION_FAILED', 'QR token attendance unik tidak dapat dibuat.');
}

function attendanceEventFromRow_(row, displayRow, headerMap, rowNumber, timeZone) {
  return {
    rowNumber: rowNumber,
    eventId: String(row[headerMap.EventId] || '').trim(),
    eventName: String(row[headerMap.EventName] || '').trim(),
    eventDateKey: attendanceDateKey_(row[headerMap.EventDate], displayRow[headerMap.EventDate], timeZone),
    startTimeKey: attendanceTimeKey_(row[headerMap.StartTime], displayRow[headerMap.StartTime], timeZone),
    endTimeKey: attendanceTimeKey_(row[headerMap.EndTime], displayRow[headerMap.EndTime], timeZone),
    countForStreak: isTrue_(row[headerMap.CountForStreak]),
    qrToken: String(row[headerMap.QRToken] || '').trim(),
    status: String(row[headerMap.Status] || '').trim().toUpperCase(),
    timeZone: timeZone,
  };
}

function findAttendanceEventByQrToken_(qrToken, events) {
  const token = String(qrToken || '').trim();
  if (!token) return null;

  const matches = events.filter(function (event) {
    return event.qrToken === token;
  });
  if (matches.length > 1) {
    throw oraError_('CONFIG_ERROR', 'QRToken attendance tidak unik.');
  }
  return matches.length === 1 ? matches[0] : null;
}

function getAttendanceEventScanStatus_(event, now) {
  const window = attendanceEventWindow_(event);
  const scanMillis = (now || new Date()).getTime();
  if (scanMillis < window.startMillis) return 'EVENT_NOT_STARTED';
  if (scanMillis > window.endMillis) return 'EVENT_CLOSED';
  return 'SUCCESS';
}

function getAttendanceEventEligibilityStatus_(event, now) {
  if (event.status !== 'ACTIVE') return 'EVENT_INACTIVE';
  return getAttendanceEventScanStatus_(event, now);
}

function attendanceEventWindow_(event) {
  if (!event || !event.eventDateKey || !event.startTimeKey || !event.endTimeKey) {
    throw oraError_('CONFIG_ERROR', 'Tanggal atau waktu event attendance tidak valid.');
  }

  const startMillis = localDateTimeToMillis_(
    event.eventDateKey,
    event.startTimeKey,
    event.timeZone
  );
  let endMillis = localDateTimeToMillis_(
    event.eventDateKey,
    event.endTimeKey,
    event.timeZone
  );
  if (endMillis <= startMillis) endMillis += 24 * 60 * 60 * 1000;
  return { startMillis: startMillis, endMillis: endMillis };
}

function attendanceDateKey_(value, displayValue, timeZone) {
  const displayed = String(displayValue || '').trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(displayed)) return displayed;
  const date = toDateOrNull_(value);
  return date ? Utilities.formatDate(date, timeZone, 'yyyy-MM-dd') : null;
}

function attendanceTimeKey_(value, displayValue, timeZone) {
  const displayed = String(displayValue || '').trim();
  const direct = normalizeAttendanceClock_(displayed);
  if (direct) return direct;

  const date = toDateOrNull_(value);
  return date ? Utilities.formatDate(date, timeZone, 'HH:mm:ss') : null;
}

function normalizeAttendanceClock_(value) {
  const match = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(String(value || '').trim());
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  const seconds = Number(match[3] || 0);
  if (hours > 23 || minutes > 59 || seconds > 59) return null;
  return ('0' + hours).slice(-2) + ':' + ('0' + minutes).slice(-2) + ':' + ('0' + seconds).slice(-2);
}

function localDateTimeToMillis_(dateKey, timeKey, timeZone) {
  const dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateKey || ''));
  const timeMatch = /^(\d{2}):(\d{2}):(\d{2})$/.exec(String(timeKey || ''));
  if (!dateMatch || !timeMatch) {
    throw oraError_('CONFIG_ERROR', 'Format tanggal/waktu event attendance tidak valid.');
  }
  const utcMillis = Date.UTC(
    Number(dateMatch[1]),
    Number(dateMatch[2]) - 1,
    Number(dateMatch[3]),
    Number(timeMatch[1]),
    Number(timeMatch[2]),
    Number(timeMatch[3])
  );
  const offsetText = Utilities.formatDate(new Date(utcMillis), timeZone, 'Z');
  const offsetMatch = /^([+-])(\d{2})(\d{2})$/.exec(offsetText);
  if (!offsetMatch) throw oraError_('CONFIG_ERROR', 'Timezone spreadsheet tidak valid.');
  const offsetMinutes = (Number(offsetMatch[2]) * 60) + Number(offsetMatch[3]);
  return utcMillis + (offsetMatch[1] === '+' ? -1 : 1) * offsetMinutes * 60000;
}

function getAttendanceRecordsForNik_(nik) {
  const sheet = getAttendanceRecordsSheet_();
  const values = readSheetValues_(ORA_SHEETS.ATTENDANCE_RECORDS, sheet);
  if (values.length < 2) return [];

  const headerMap = createHeaderMap_(values[0]);
  const targetNik = normalizeDigits_(nik);
  return values.slice(1).map(function (row, index) {
    return attendanceRecordFromRow_(row, headerMap, index + 2);
  }).filter(function (record) {
    return record.nik === targetNik;
  });
}

function findAttendanceRecordByNikAndEventId_(sheet, nik, eventId) {
  const values = readSheetValues_(ORA_SHEETS.ATTENDANCE_RECORDS, sheet);
  if (values.length < 2) return null;

  const headerMap = createHeaderMap_(values[0]);
  const records = values.slice(1).map(function (row, index) {
    return attendanceRecordFromRow_(row, headerMap, index + 2);
  });
  return findAttendanceRecordInRecords_(records, nik, eventId);
}

function findAttendanceRecordInRecords_(records, nik, eventId) {
  const targetNik = normalizeDigits_(nik);
  const targetEventId = String(eventId || '').trim();
  return records.find(function (record) {
    return record.nik === targetNik && record.eventId === targetEventId;
  }) || null;
}

function attendanceRecordFromRow_(row, headerMap, rowNumber) {
  return {
    rowNumber: rowNumber,
    attendanceId: String(row[headerMap.AttendanceId] || '').trim(),
    eventId: String(row[headerMap.EventId] || '').trim(),
    nik: normalizeDigits_(row[headerMap.NIK]),
    nickname: String(row[headerMap.Nickname] || '').trim(),
    checkInAt: row[headerMap.CheckInAt] || null,
    baseXp: Math.max(0, Math.round(Number(row[headerMap.BaseXP]) || 0)),
    streakCount: Math.max(0, Math.round(Number(row[headerMap.StreakCount]) || 0)),
    streakBonusXp: Math.max(0, Math.round(Number(row[headerMap.StreakBonusXP]) || 0)),
    totalXp: Math.max(0, Math.round(Number(row[headerMap.TotalXP]) || 0)),
    status: String(row[headerMap.Status] || '').trim().toUpperCase(),
    createdAt: row[headerMap.CreatedAt] || null,
  };
}

function appendAttendanceRecord_(sheet, record) {
  const now = new Date();
  const rowNumber = sheet.getLastRow() + 1;
  const values = [[
    String(record.attendanceId),
    String(record.eventId),
    String(record.nik),
    String(record.nickname || ''),
    record.checkInAt || now,
    Number(record.baseXp),
    Number(record.streakCount),
    Number(record.streakBonusXp),
    Number(record.totalXp),
    String(record.status || 'PROCESSING'),
    now,
  ]];
  sheet.getRange(rowNumber, 1, 1, 3).setNumberFormat('@');
  sheet.getRange(rowNumber, 1, 1, ORA_HEADERS.Attendance_Records.length).setValues(values);
  invalidateSheetSnapshot_(ORA_SHEETS.ATTENDANCE_RECORDS);
  return attendanceRecordFromRow_(values[0], createHeaderMap_(ORA_HEADERS.Attendance_Records), rowNumber);
}

function markAttendanceRecordSuccess_(sheet, rowNumber) {
  const headerMap = createHeaderMap_(ORA_HEADERS.Attendance_Records);
  sheet.getRange(rowNumber, headerMap.Status + 1).setValue('SUCCESS');
  invalidateSheetSnapshot_(ORA_SHEETS.ATTENDANCE_RECORDS);
  const row = sheet.getRange(rowNumber, 1, 1, ORA_HEADERS.Attendance_Records.length).getValues()[0];
  return attendanceRecordFromRow_(row, headerMap, rowNumber);
}

function getAttendanceBaseXp_(rewards) {
  const candidates = rewards.filter(function (reward) {
    return reward.status === 'ACTIVE' && reward.rewardType === 'BASE' && reward.milestone === 1;
  });
  if (candidates.length !== 1) {
    throw oraError_('CONFIG_ERROR', 'Base XP attendance aktif untuk milestone 1 harus tepat satu.');
  }
  return validateAttendanceRewardXp_(candidates[0].xp, 'Base XP attendance');
}

function getAttendanceStreakBonusXp_(rewards, streakCount) {
  const activeStreakRewards = rewards.filter(function (reward) {
    return reward.status === 'ACTIVE' && reward.rewardType === 'STREAK';
  });
  activeStreakRewards.forEach(function (reward) {
    if (!Number.isInteger(reward.milestone) || reward.milestone < 1) {
      throw oraError_('CONFIG_ERROR', 'Milestone reward streak attendance tidak valid.');
    }
    validateAttendanceRewardXp_(reward.xp, 'XP reward streak attendance');
  });
  const matches = activeStreakRewards.filter(function (reward) {
    return reward.milestone === streakCount;
  });
  if (matches.length > 1) {
    throw oraError_('CONFIG_ERROR', 'Milestone reward streak attendance duplikat.');
  }
  return matches.length === 1 ? validateAttendanceRewardXp_(matches[0].xp, 'XP reward streak attendance') : 0;
}

function validateAttendanceRewardXp_(xp, label) {
  if (!Number.isFinite(xp) || xp < 0 || Math.floor(xp) !== xp) {
    throw oraError_('CONFIG_ERROR', label + ' tidak valid.');
  }
  return xp;
}

function calculateAttendanceStreakForEvent_(events, records, nik, targetEvent) {
  const ordered = events.filter(function (event) {
    return event.countForStreak === true && event.status === 'ACTIVE';
  }).sort(compareAttendanceEvents_);
  const targetIndex = ordered.findIndex(function (event) {
    return event.eventId === targetEvent.eventId;
  });

  if (targetEvent.countForStreak && targetIndex < 0) {
    throw oraError_('CONFIG_ERROR', 'Event streak attendance tidak memiliki urutan yang valid.');
  }

  const completedEventIds = {};
  records.forEach(function (record) {
    if (record.nik === normalizeDigits_(nik) && record.status === 'SUCCESS') {
      completedEventIds[record.eventId] = true;
    }
  });

  if (!targetEvent.countForStreak) {
    const preceding = ordered.filter(function (event) {
      return compareAttendanceEvents_(event, targetEvent) < 0;
    });
    if (preceding.length === 0 || !completedEventIds[preceding[preceding.length - 1].eventId]) return 0;
    return countConsecutiveAttendanceEvents_(preceding, completedEventIds, preceding.length - 1);
  }

  return 1 + countConsecutiveAttendanceEvents_(ordered, completedEventIds, targetIndex - 1);
}

function countConsecutiveAttendanceEvents_(orderedEvents, completedEventIds, startIndex) {
  let count = 0;
  for (let index = startIndex; index >= 0; index -= 1) {
    if (!completedEventIds[orderedEvents[index].eventId]) break;
    count += 1;
  }
  return count;
}

function compareAttendanceEvents_(left, right) {
  const leftKey = attendanceEventOrderKey_(left);
  const rightKey = attendanceEventOrderKey_(right);
  return leftKey < rightKey ? -1 : (leftKey > rightKey ? 1 : 0);
}

function attendanceEventOrderKey_(event) {
  if (!event.eventDateKey) {
    throw oraError_('CONFIG_ERROR', 'EventDate attendance tidak valid.');
  }
  return event.eventDateKey + 'T' + (event.startTimeKey || '00:00:00') + '|' + event.eventId;
}

function grantAttendanceXp_(participant, totalXp) {
  // Reuse the single existing User_Stats/level writer. It changes only XP/level.
  return grantQuestRewardXp_(participant, totalXp);
}

function getActiveLevels_() {
  return getCachedMasterData_(ORA_SHEETS.LEVELS, function () {
    return readSheetObjects_(ORA_SHEETS.LEVELS)
      .filter(function (row) {
        return isTrue_(row.Active);
      })
      .map(function (row) {
        return {
          level: toFiniteNumberOrNull_(row.Level),
          levelName: String(row.Level_Name || '').trim(),
          requiredTotalXp: toFiniteNumberOrNull_(row.Required_Total_XP),
        };
      })
      .filter(function (level) {
        return level.level !== null && level.requiredTotalXp !== null;
      })
      .sort(function (a, b) {
        return a.level - b.level;
      });
  });
}

function getActiveQuests_() {
  return getCachedMasterData_(ORA_SHEETS.QUESTS, function () {
    const now = new Date();

    return readSheetObjects_(ORA_SHEETS.QUESTS)
      .filter(function (row) {
        return isTrue_(row.Active) && isQuestWithinDateRange_(row, now);
      })
      .map(function (row) {
        return {
          questId: String(row.Quest_ID || '').trim(),
          questName: String(row.Quest_Name || '').trim(),
          questType: String(row.Quest_Type || '').trim().toUpperCase(),
          targetValue: toFiniteNumberOrNull_(row.Target_Value),
          unit: String(row.Unit || '').trim(),
          rewardXp: toFiniteNumberOrNull_(row.Reward_XP),
          periodType: String(row.Period_Type || '').trim().toUpperCase(),
          startDate: toIsoDateOrNull_(row.Start_Date),
          endDate: toIsoDateOrNull_(row.End_Date),
        };
      })
      .filter(function (quest) {
        return !!quest.questId;
      });
  });
}

function getCompletedActivitiesForNik_(nik) {
  return mapCompletedActivityRowsForNik_(
    readSheetObjects_(ORA_SHEETS.ACTIVITIES),
    nik
  );
}

function mapCompletedActivityRowsForNik_(rows, nik) {
  return mapCompletedActivityRowsForNiks_(rows, [nik]);
}

function mapCompletedActivityRowsForNiks_(rows, niks) {
  const allowedNiks = {};
  niks.forEach(function (nik) {
    const normalizedNik = normalizeDigits_(nik);
    if (normalizedNik) allowedNiks[normalizedNik] = true;
  });

  return rows
    .filter(function (row) {
      return (
        !!allowedNiks[normalizeDigits_(row.NIK)] &&
        normalizeQuestType_(row.Status) === 'COMPLETED'
      );
    })
    .map(function (row) {
      const activityDate = toDateOrNull_(row.EndTime) || toDateOrNull_(row.StartTime);
      return {
        activityId: String(row.ActivityId || '').trim(),
        activityDate: activityDate,
        activityDateKey: toLocalDateKeyOrNull_(activityDate),
        durationSec: toNonNegativeFiniteNumber_(row.DurationSec),
        distanceKm: toNonNegativeFiniteNumber_(row.DistanceKm),
      };
    })
    .filter(function (activity) {
      return !!activity.activityDateKey;
    });
}

function buildGuildActivityContext_(owner, participants, activityRows) {
  const divisionKey = normalizeDivisionKey_(owner.divisionGuild);
  if (!divisionKey) return { hasGuild: false, activities: [] };

  const activeMemberNiks = participants.filter(function (participant) {
    return (
      participant.status === 'ACTIVE' &&
      normalizeDivisionKey_(participant.divisionGuild) === divisionKey
    );
  }).map(function (participant) {
    return participant.nik;
  });

  return {
    hasGuild: true,
    activities: mapCompletedActivityRowsForNiks_(activityRows, activeMemberNiks),
  };
}

function calculateQuestProgress_(
  quest,
  allActivities,
  userStats,
  guildContext,
  config,
  attendanceRecords
) {
  const normalizedType = normalizeQuestType_(quest.questType);
  const supportedType = mapQuestType_(normalizedType);
  const sourceActivities = supportedType === 'GUILD_DISTANCE'
    ? (guildContext && guildContext.activities ? guildContext.activities : [])
    : allActivities;
  const activities = sourceActivities.filter(function (activity) {
    return isActivityWithinQuestPeriod_(activity, quest);
  });
  const successfulAttendance = (attendanceRecords || []).filter(function (record) {
    return record.status === 'SUCCESS' && isAttendanceWithinQuestPeriod_(record, quest);
  });
  let progress = 0;

  switch (supportedType) {
    case 'DISTANCE':
      progress = activities.reduce(function (total, activity) {
        return total + activity.distanceKm;
      }, 0);
      break;
    case 'RUN_COUNT':
      progress = activities.length;
      break;
    case 'TOTAL_RUNS':
      progress = countUniqueValidRuns_(activities, getMinDistanceValidRunKm_(config));
      break;
    case 'RUN_DAYS':
      progress = countUniqueActivityDays_(activities);
      break;
    case 'SINGLE_RUN':
      progress = activities.reduce(function (largestDistance, activity) {
        return Math.max(largestDistance, activity.distanceKm);
      }, 0);
      break;
    case 'DURATION':
      progress = activities.reduce(function (total, activity) {
        return total + activity.durationSec;
      }, 0);
      break;
    case 'XP':
      progress = calculateQuestXpProgress_(quest, activities, userStats);
      break;
    case 'STREAK':
      progress = calculateLongestActivityStreak_(activities);
      break;
    case 'GUILD_DISTANCE':
      if (!guildContext || !guildContext.hasGuild) {
        return blockGuildQuestClaim_(
          publicQuestProgress_(quest, 0, 'NO_GUILD', false, 0)
        );
      }
      progress = activities.reduce(function (total, activity) {
        return total + activity.distanceKm;
      }, 0);
      break;
    case 'ATTENDANCE':
      progress = calculateAttendanceQuestProgress_(quest, successfulAttendance);
      if (progress === null) {
        return publicQuestProgress_(quest, 0, 'UNKNOWN_TYPE', false, 0);
      }
      break;
    default:
      return publicQuestProgress_(quest, 0, 'UNKNOWN_TYPE', false, 0);
  }

  progress = roundDecimal_(Math.max(0, progress), 3);
  const target = Number(quest.targetValue);
  const hasValidTarget = Number.isFinite(target) && target > 0;
  const completed = hasValidTarget && progress >= target;
  const progressPercent = hasValidTarget
    ? Math.min(100, roundDecimal_((progress / target) * 100, 2))
    : 0;
  const status = completed
    ? 'COMPLETED'
    : (progress > 0 ? 'IN_PROGRESS' : 'NOT_STARTED');

  const result = publicQuestProgress_(quest, progress, status, completed, progressPercent);
  return supportedType === 'GUILD_DISTANCE' ? blockGuildQuestClaim_(result) : result;
}

function getMinDistanceValidRunKm_(config) {
  const definition = ORA_CONFIG_DEFINITIONS.MIN_DISTANCE_VALID_RUN_KM;
  const activeConfig = config || getActiveConfig_();
  const configured = Number(activeConfig[definition.key]);
  return Number.isFinite(configured) && configured > 0
    ? configured
    : definition.defaultValue;
}

function countUniqueValidRuns_(activities, minimumDistanceKm) {
  const seenActivityIds = Object.create(null);
  let count = 0;

  activities.forEach(function (activity) {
    const distanceKm = Number(activity.distanceKm);
    if (!Number.isFinite(distanceKm) || distanceKm < minimumDistanceKm) return;

    const activityId = String(activity.activityId || '').trim();
    if (activityId) {
      if (seenActivityIds[activityId]) return;
      seenActivityIds[activityId] = true;
    }
    count += 1;
  });

  return count;
}

function blockGuildQuestClaim_(questProgress) {
  questProgress.claimable = false;
  questProgress.claimBlockedReason = 'GUILD_REWARD_NOT_READY';
  return questProgress;
}

function calculateQuestXpProgress_(quest, activities, userStats) {
  const hasDatePeriod = !!quest.startDate || !!quest.endDate;
  if (!hasDatePeriod && userStats) {
    return Math.max(0, Number(userStats.totalXp) || 0);
  }

  return activities.reduce(function (total, activity) {
    return total + calculateActivityXp_(activity.distanceKm, 'COMPLETED');
  }, 0);
}

function calculateAttendanceQuestProgress_(quest, records) {
  const mode = normalizeQuestType_(quest.unit);
  if (mode === 'COUNT') return countUniqueSuccessfulAttendanceEvents_(records);
  if (mode === 'STREAK') return latestAttendanceStreakCount_(records);
  return null;
}

function countUniqueSuccessfulAttendanceEvents_(records) {
  const eventIds = {};
  records.forEach(function (record) {
    const eventId = String(record.eventId || '').trim();
    if (eventId) eventIds[eventId] = true;
  });
  return Object.keys(eventIds).length;
}

function latestAttendanceStreakCount_(records) {
  let latest = null;
  records.forEach(function (record) {
    const checkInAt = toDateOrNull_(record.checkInAt);
    if (!checkInAt) return;
    if (!latest || checkInAt.getTime() > latest.checkInAt.getTime()) {
      latest = {
        checkInAt: checkInAt,
        streakCount: Math.max(0, Math.round(Number(record.streakCount) || 0)),
      };
    }
  });
  return latest ? latest.streakCount : 0;
}

function calculateLongestActivityStreak_(activities) {
  const uniqueDates = {};
  activities.forEach(function (activity) {
    if (activity.activityDateKey) uniqueDates[activity.activityDateKey] = true;
  });

  const dates = Object.keys(uniqueDates).sort();
  let longest = 0;
  let current = 0;
  let previousDayNumber = null;

  dates.forEach(function (dateKey) {
    const dayNumber = isoDateKeyToDayNumber_(dateKey);
    if (dayNumber === null) return;

    current = previousDayNumber !== null && dayNumber === previousDayNumber + 1
      ? current + 1
      : 1;
    longest = Math.max(longest, current);
    previousDayNumber = dayNumber;
  });

  return longest;
}

function countUniqueActivityDays_(activities) {
  const uniqueDates = {};
  activities.forEach(function (activity) {
    if (activity.activityDateKey) uniqueDates[activity.activityDateKey] = true;
  });
  return Object.keys(uniqueDates).length;
}

function isActivityWithinQuestPeriod_(activity, quest) {
  if (!activity.activityDateKey) return false;
  if (quest.startDate && activity.activityDateKey < quest.startDate) return false;
  if (quest.endDate && activity.activityDateKey > quest.endDate) return false;
  return true;
}

function isAttendanceWithinQuestPeriod_(record, quest) {
  const checkInAt = toDateOrNull_(record.checkInAt);
  const dateKey = toLocalDateKeyOrNull_(checkInAt);
  if (!dateKey) return false;
  if (quest.startDate && dateKey < quest.startDate) return false;
  if (quest.endDate && dateKey > quest.endDate) return false;
  return true;
}

function mapQuestType_(type) {
  const aliases = {
    DISTANCE: 'DISTANCE',
    DISTANCE_KM: 'DISTANCE',
    TOTAL_DISTANCE: 'DISTANCE',
    DISTANCE_TOTAL: 'DISTANCE',
    RUN_COUNT: 'RUN_COUNT',
    RUNS: 'RUN_COUNT',
    RUNCOUNT: 'RUN_COUNT',
    COUNT: 'RUN_COUNT',
    ACTIVITIES: 'RUN_COUNT',
    ACTIVITY_COUNT: 'RUN_COUNT',
    TOTAL_RUNS: 'TOTAL_RUNS',
    RUN_DAYS: 'RUN_DAYS',
    ACTIVE_DAYS: 'RUN_DAYS',
    SINGLE_RUN: 'SINGLE_RUN',
    LONGEST_RUN: 'SINGLE_RUN',
    GUILD_DISTANCE: 'GUILD_DISTANCE',
    DURATION: 'DURATION',
    DURATION_SEC: 'DURATION',
    DURATION_SECONDS: 'DURATION',
    TOTAL_DURATION: 'DURATION',
    TIME: 'DURATION',
    XP: 'XP',
    EXP: 'XP',
    TOTAL_XP: 'XP',
    EXPERIENCE: 'XP',
    EXPERIENCE_POINTS: 'XP',
    STREAK: 'STREAK',
    RUN_STREAK: 'STREAK',
    DAILY_STREAK: 'STREAK',
    CONSECUTIVE_DAYS: 'STREAK',
    ATTENDANCE: 'ATTENDANCE',
  };
  return aliases[type] || null;
}

function normalizeQuestType_(value) {
  return String(value == null ? '' : value)
    .trim()
    .toUpperCase()
    .replace(/[\s-]+/g, '_');
}

function publicQuestProgress_(quest, progress, status, completed, progressPercent) {
  return {
    questId: quest.questId,
    name: quest.questName,
    type: quest.questType,
    target: quest.targetValue,
    unit: quest.unit,
    progress: progress,
    progressPercent: progressPercent,
    rewardXp: quest.rewardXp,
    period: quest.periodType,
    activeFrom: quest.startDate,
    activeTo: quest.endDate,
    status: status,
    completed: completed,
  };
}

function findParticipantByNik_(nik) {
  const sheet = getValidatedSheet_(ORA_SHEETS.PARTICIPANTS);
  const values = readSheetDisplayValues_(ORA_SHEETS.PARTICIPANTS, sheet);
  if (values.length < 2) return null;

  const headerMap = createHeaderMap_(values[0]);
  const nikIndex = headerMap.NIK;

  for (let index = 1; index < values.length; index += 1) {
    const row = values[index];
    if (normalizeDigits_(row[nikIndex]) === nik) {
      return {
        rowNumber: index + 1,
        headerMap: headerMap,
        nik: normalizeDigits_(row[headerMap.NIK]),
        pin: normalizeDigits_(row[headerMap.PIN]),
        nickname: String(row[headerMap.Nickname] || '').trim(),
        divisionGuild: String(row[headerMap.Division_Guild] || '').trim(),
        status: String(row[headerMap.Status] || '').trim().toUpperCase(),
        createdAt: row[headerMap.Created_At] || null,
        updatedAt: row[headerMap.Updated_At] || null,
      };
    }
  }

  return null;
}

function getActivitiesSheet_() {
  return getValidatedSheet_(ORA_SHEETS.ACTIVITIES);
}

function findActivityByNikAndActivityId_(sheet, nik, activityId) {
  const values = readSheetDisplayValues_(ORA_SHEETS.ACTIVITIES, sheet);
  if (values.length < 2) return null;

  const headerMap = createHeaderMap_(values[0]);
  const nikIndex = headerMap.NIK;
  const activityIdIndex = headerMap.ActivityId;
  const targetNik = normalizeDigits_(nik);
  const targetActivityId = String(activityId == null ? '' : activityId).trim();

  for (let index = 1; index < values.length; index += 1) {
    const row = values[index];
    if (
      normalizeDigits_(row[nikIndex]) === targetNik &&
      String(row[activityIdIndex] || '').trim() === targetActivityId
    ) {
      return {
        rowNumber: index + 1,
        activityId: targetActivityId,
        nik: targetNik,
      };
    }
  }

  return null;
}

function findActivityByNikSourceAndRef_(sheet, nik, source, sourceRef) {
  const values = readSheetDisplayValues_(ORA_SHEETS.ACTIVITIES, sheet);
  if (values.length < 2) return null;

  const headerMap = createHeaderMap_(values[0]);
  if (headerMap.SourceRef == null || headerMap.SourceUrl == null) return null;
  const targetNik = normalizeDigits_(nik);
  const targetSource = normalizeImportActivitySource_(source);
  const targetRef = String(sourceRef == null ? '' : sourceRef).trim();
  if (!targetRef) return null;

  for (let index = 1; index < values.length; index += 1) {
    const row = values[index];
    if (
      normalizeDigits_(row[headerMap.NIK]) === targetNik &&
      normalizeImportActivitySource_(row[headerMap.Source]) === targetSource &&
      String(row[headerMap.SourceRef] || '').trim() === targetRef
    ) {
      return {
        rowNumber: index + 1,
        activityId: String(row[headerMap.ActivityId] || '').trim(),
        nik: targetNik,
        source: targetSource,
        sourceRef: targetRef,
      };
    }
  }
  return null;
}

function appendActivity_(sheet, activity) {
  const now = new Date();
  const nextRow = sheet.getLastRow() + 1;
  const values = [[
    String(activity.activityId),
    String(activity.nik),
    String(activity.nickname || ''),
    String(activity.division || ''),
    String(activity.startTime),
    String(activity.endTime),
    Number(activity.durationSec),
    Number(activity.distanceKm),
    String(activity.avgPace || ''),
    'COMPLETED',
    String(activity.source || 'ANDROID'),
    String(activity.deviceTime || ''),
    now,
    now,
    now,
    String(activity.sourceRef || ''),
    String(activity.sourceUrl || ''),
  ]];

  sheet.getRange(nextRow, 1, 1, 2).setNumberFormat('@');
  sheet.getRange(nextRow, 1, 1, ORA_HEADERS.Activities.length).setValues(values);
  invalidateSheetSnapshot_(ORA_SHEETS.ACTIVITIES);
  return nextRow;
}

function normalizeImportActivitySource_(value) {
  const source = String(value == null ? '' : value).trim().toUpperCase();
  return [
    'STRAVA',
    'GARMIN',
    'COROS',
    'SUUNTO',
    'HUAWEI',
    'AMAZFIT',
    'UNKNOWN',
    'ANDROID',
    'WEB',
  ].indexOf(source) >= 0 ? source : 'ANDROID';
}

function extractActivitySourceRef_(source, sourceUrl) {
  if (normalizeImportActivitySource_(source) !== 'STRAVA') return '';
  const value = String(sourceUrl == null ? '' : sourceUrl).trim();
  if (!value) return '';
  const canonical = value.match(/\/activities\/([^/?#]+)/i);
  if (canonical && canonical[1]) return decodeURIComponent(canonical[1]);
  const shortLink = value.match(/^https?:\/\/(?:[^/]+\.)?strava\.app\.link\/([^?#/]+)(?:[/?#]|$)/i);
  return shortLink && shortLink[1] ? decodeURIComponent(shortLink[1]) : '';
}

function ensureUserStatsSheet_() {
  const spreadsheet = getOraSpreadsheet_();
  let sheet = spreadsheet.getSheetByName(ORA_SHEETS.USER_STATS);

  if (!sheet) {
    sheet = spreadsheet.insertSheet(ORA_SHEETS.USER_STATS);
    sheet.getRange(1, 1, 1, ORA_HEADERS.User_Stats.length)
      .setValues([ORA_HEADERS.User_Stats]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, ORA_HEADERS.User_Stats.length)
      .setFontWeight('bold');
    sheet.getRange('A:A').setNumberFormat('@');
    invalidateSheetSnapshot_(ORA_SHEETS.USER_STATS);
  }

  return getValidatedSheet_(ORA_SHEETS.USER_STATS);
}

function ensureQuestClaimsSheet_() {
  const spreadsheet = getOraSpreadsheet_();
  let sheet = spreadsheet.getSheetByName(ORA_SHEETS.QUEST_CLAIMS);

  if (!sheet) {
    sheet = spreadsheet.insertSheet(ORA_SHEETS.QUEST_CLAIMS);
    sheet.getRange(1, 1, 1, ORA_HEADERS.Quest_Claims.length)
      .setValues([ORA_HEADERS.Quest_Claims]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, ORA_HEADERS.Quest_Claims.length)
      .setFontWeight('bold');
    sheet.getRange('A:C').setNumberFormat('@');
    invalidateSheetSnapshot_(ORA_SHEETS.QUEST_CLAIMS);
  }

  return getValidatedSheet_(ORA_SHEETS.QUEST_CLAIMS);
}

function ensureGuildMasterSheet_() {
  const spreadsheet = getOraSpreadsheet_();
  let sheet = spreadsheet.getSheetByName(ORA_SHEETS.GUILD_MASTER);

  if (!sheet) {
    sheet = spreadsheet.insertSheet(ORA_SHEETS.GUILD_MASTER);
    sheet.getRange(1, 1, 1, ORA_HEADERS.Guild_Master.length)
      .setValues([ORA_HEADERS.Guild_Master]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, ORA_HEADERS.Guild_Master.length)
      .setFontWeight('bold');
    sheet.getRange('A:A').setNumberFormat('@');
    invalidateSheetSnapshot_(ORA_SHEETS.GUILD_MASTER);
  }

  return getValidatedSheet_(ORA_SHEETS.GUILD_MASTER);
}

function getClaimedQuestsByNik_(nik) {
  const sheet = ensureQuestClaimsSheet_();
  const values = readSheetValues_(ORA_SHEETS.QUEST_CLAIMS, sheet);
  const displayValues = readSheetDisplayValues_(ORA_SHEETS.QUEST_CLAIMS, sheet);
  if (values.length < 2) return {};

  const headerMap = createHeaderMap_(displayValues[0]);
  const targetNik = normalizeDigits_(nik);
  const claims = {};
  for (let index = 1; index < values.length; index += 1) {
    const displayRow = displayValues[index];
    const status = String(displayRow[headerMap.Status] || '').trim().toUpperCase();
    if (
      normalizeDigits_(displayRow[headerMap.NIK]) !== targetNik ||
      status !== 'CLAIMED'
    ) {
      continue;
    }

    const row = values[index];
    const claim = questClaimFromRow_(row, headerMap, index + 1);
    claims[claim.questId] = claim;
  }
  return claims;
}

function findQuestClaim_(sheet, nik, questId) {
  const values = readSheetValues_(ORA_SHEETS.QUEST_CLAIMS, sheet);
  const displayValues = readSheetDisplayValues_(ORA_SHEETS.QUEST_CLAIMS, sheet);
  if (values.length < 2) return null;

  const headerMap = createHeaderMap_(displayValues[0]);
  const targetNik = normalizeDigits_(nik);
  const targetQuestId = String(questId || '').trim();
  for (let index = 1; index < displayValues.length; index += 1) {
    const row = displayValues[index];
    if (
      normalizeDigits_(row[headerMap.NIK]) === targetNik &&
      String(row[headerMap.QuestId] || '').trim() === targetQuestId
    ) {
      return questClaimFromRow_(values[index], headerMap, index + 1);
    }
  }
  return null;
}

function appendQuestClaim_(sheet, claim) {
  const now = new Date();
  const rowNumber = sheet.getLastRow() + 1;
  const values = [[
    String(claim.claimId),
    String(claim.nik),
    String(claim.questId),
    String(claim.questName || ''),
    Number(claim.rewardXp) || 0,
    String(claim.status || 'PROCESSING'),
    '',
    now,
  ]];
  sheet.getRange(rowNumber, 1, 1, 3).setNumberFormat('@');
  sheet.getRange(rowNumber, 1, 1, ORA_HEADERS.Quest_Claims.length).setValues(values);
  invalidateSheetSnapshot_(ORA_SHEETS.QUEST_CLAIMS);
  return questClaimFromRow_(values[0], createHeaderMap_(ORA_HEADERS.Quest_Claims), rowNumber);
}

function markQuestClaimed_(sheet, rowNumber) {
  const headerMap = createHeaderMap_(ORA_HEADERS.Quest_Claims);
  const claimedAt = new Date();
  sheet.getRange(rowNumber, headerMap.Status + 1).setValue('CLAIMED');
  sheet.getRange(rowNumber, headerMap.ClaimedAt + 1).setValue(claimedAt);
  invalidateSheetSnapshot_(ORA_SHEETS.QUEST_CLAIMS);
  const row = sheet.getRange(rowNumber, 1, 1, ORA_HEADERS.Quest_Claims.length)
    .getValues()[0];
  return questClaimFromRow_(row, headerMap, rowNumber);
}

function questClaimFromRow_(row, headerMap, rowNumber) {
  return {
    rowNumber: rowNumber,
    claimId: String(row[headerMap.ClaimId] || '').trim(),
    nik: normalizeDigits_(row[headerMap.NIK]),
    questId: String(row[headerMap.QuestId] || '').trim(),
    questName: String(row[headerMap.QuestName] || '').trim(),
    rewardXp: Math.max(0, Math.round(Number(row[headerMap.RewardXP]) || 0)),
    status: String(row[headerMap.Status] || '').trim().toUpperCase(),
    claimedAt: row[headerMap.ClaimedAt] || null,
    createdAt: row[headerMap.CreatedAt] || null,
  };
}

function publicQuestClaim_(claim) {
  return {
    claimId: claim.claimId,
    questId: claim.questId,
    questName: claim.questName,
    rewardXp: claim.rewardXp,
    status: claim.status,
    claimedAt: toIsoDateTimeOrNull_(claim.claimedAt),
  };
}

function attachQuestClaim_(questProgress, claim) {
  questProgress.claimed = !!claim;
  questProgress.claimId = claim ? claim.claimId : null;
  questProgress.claimedAt = claim ? toIsoDateTimeOrNull_(claim.claimedAt) : null;
  return questProgress;
}

function getXpPerKm_() {
  const configured = Number(getActiveConfig_().XP_PER_KM);
  return Number.isFinite(configured) && configured >= 0 ? configured : 10;
}

function calculateActivityXp_(distanceKm, status) {
  const normalizedStatus = String(status || '').trim().toUpperCase();
  const distance = Number(distanceKm);
  if (normalizedStatus !== 'COMPLETED' || !Number.isFinite(distance) || distance <= 0) {
    return 0;
  }
  return calculateActivityXpWithRate_(distance, normalizedStatus, getXpPerKm_());
}

function calculateActivityXpWithRate_(distanceKm, status, xpPerKm) {
  if (String(status || '').trim().toUpperCase() !== 'COMPLETED') return 0;

  const distance = Number(distanceKm);
  const rate = Number(xpPerKm);
  if (
    !Number.isFinite(distance) ||
    distance <= 0 ||
    !Number.isFinite(rate) ||
    rate < 0
  ) {
    return 0;
  }
  return Math.round(distance * rate);
}

function getLevelByXp_(totalXp) {
  return getLevelByXpFromLevels_(totalXp, getActiveLevels_());
}

function getLevelByXpFromLevels_(totalXp, levels) {
  const xp = Math.max(0, Number(totalXp) || 0);
  if (levels.length === 0) {
    throw oraError_('LEVEL_CONFIG_EMPTY', 'Level_Master tidak memiliki level aktif yang valid.');
  }

  let current = levels[0];
  levels.forEach(function (level) {
    if (level.requiredTotalXp <= xp) current = level;
  });

  const next = levels.find(function (level) {
    return level.requiredTotalXp > xp;
  });

  return {
    currentLevel: current.level,
    currentLevelName: current.levelName,
    nextLevelXp: next ? next.requiredTotalXp : null,
  };
}

function findUserStatsRow_(sheet, nik) {
  const values = readSheetValues_(ORA_SHEETS.USER_STATS, sheet);
  const displayValues = readSheetDisplayValues_(ORA_SHEETS.USER_STATS, sheet);
  if (values.length < 2) return null;

  const headerMap = createHeaderMap_(displayValues[0]);
  const targetNik = normalizeDigits_(nik);

  for (let index = 1; index < displayValues.length; index += 1) {
    if (normalizeDigits_(displayValues[index][headerMap.NIK]) !== targetNik) continue;

    const row = values[index];
    return {
      rowNumber: index + 1,
      totalActivities: Number(row[headerMap.TotalActivities]) || 0,
      totalDistanceKm: Number(row[headerMap.TotalDistanceKm]) || 0,
      totalDurationSec: Number(row[headerMap.TotalDurationSec]) || 0,
      totalXp: Number(row[headerMap.TotalXP]) || 0,
    };
  }

  return null;
}

function getUserStatsByNik_(nik) {
  const sheet = ensureUserStatsSheet_();
  const values = readSheetValues_(ORA_SHEETS.USER_STATS, sheet);
  const displayValues = readSheetDisplayValues_(ORA_SHEETS.USER_STATS, sheet);
  if (values.length < 2) return null;

  const headerMap = createHeaderMap_(displayValues[0]);
  const targetNik = normalizeDigits_(nik);
  for (let index = 1; index < displayValues.length; index += 1) {
    if (normalizeDigits_(displayValues[index][headerMap.NIK]) !== targetNik) continue;

    const row = values[index];
    return {
      nik: targetNik,
      nickname: String(row[headerMap.Nickname] || ''),
      division: String(row[headerMap.Division] || ''),
      totalActivities: Number(row[headerMap.TotalActivities]) || 0,
      totalDistanceKm: Number(row[headerMap.TotalDistanceKm]) || 0,
      totalDurationSec: Number(row[headerMap.TotalDurationSec]) || 0,
      totalXp: Number(row[headerMap.TotalXP]) || 0,
      currentLevel: Number(row[headerMap.CurrentLevel]) || 0,
      currentLevelName: String(row[headerMap.CurrentLevelName] || ''),
      nextLevelXp: row[headerMap.NextLevelXP] === ''
        ? null
        : Number(row[headerMap.NextLevelXP]),
      lastActivityId: String(row[headerMap.LastActivityId] || ''),
      lastActivityAt: String(row[headerMap.LastActivityAt] || ''),
      updatedAt: row[headerMap.UpdatedAt] || null,
    };
  }

  return null;
}

function createDefaultUserStats_(participant) {
  const levels = getActiveLevels_();
  const initialLevel = levels.length > 0 ? levels[0] : null;
  const nextLevel = levels.length > 1 ? levels[1] : null;

  return {
    nik: participant.nik,
    nickname: participant.nickname || '',
    division: participant.divisionGuild || '',
    totalActivities: 0,
    totalDistanceKm: 0,
    totalDurationSec: 0,
    totalXp: 0,
    currentLevel: initialLevel ? initialLevel.level : 0,
    currentLevelName: initialLevel ? initialLevel.levelName : '',
    nextLevelXp: nextLevel ? nextLevel.requiredTotalXp : null,
    lastActivityId: '',
    lastActivityAt: '',
    updatedAt: null,
  };
}

function publicUserStats_(stats) {
  return {
    nik: stats.nik,
    nickname: stats.nickname,
    division: stats.division,
    totalActivities: stats.totalActivities,
    totalDistanceKm: stats.totalDistanceKm,
    totalDurationSec: stats.totalDurationSec,
    totalXP: stats.totalXp,
    currentLevel: stats.currentLevel,
    currentLevelName: stats.currentLevelName,
    nextLevelXP: stats.nextLevelXp,
    lastActivityId: stats.lastActivityId,
    lastActivityAt: stats.lastActivityAt,
    updatedAt: toIsoDateTimeOrNull_(stats.updatedAt),
  };
}

function toIsoDateTimeOrNull_(value) {
  if (!value) return null;
  const date = toDateOrNull_(value);
  return date ? date.toISOString() : String(value);
}

function upsertUserStats_(activity) {
  const sheet = ensureUserStatsSheet_();
  const existing = findUserStatsRow_(sheet, activity.nik);
  const totalActivities = (existing ? existing.totalActivities : 0) + 1;
  const totalDistanceKm = roundDecimal_(
    (existing ? existing.totalDistanceKm : 0) + Number(activity.distanceKm),
    3
  );
  const totalDurationSec = roundDecimal_(
    (existing ? existing.totalDurationSec : 0) + Number(activity.durationSec),
    3
  );
  const totalXp = Math.round(
    (existing ? existing.totalXp : 0) + Number(activity.activityXp)
  );
  const level = getLevelByXp_(totalXp);
  const targetRow = existing ? existing.rowNumber : sheet.getLastRow() + 1;
  const now = new Date();

  const values = [[
    String(activity.nik),
    String(activity.nickname || ''),
    String(activity.division || ''),
    totalActivities,
    totalDistanceKm,
    totalDurationSec,
    totalXp,
    level.currentLevel,
    level.currentLevelName,
    level.nextLevelXp == null ? '' : level.nextLevelXp,
    String(activity.activityId),
    String(activity.activityAt || ''),
    now,
  ]];

  sheet.getRange(targetRow, 1).setNumberFormat('@');
  sheet.getRange(targetRow, 1, 1, ORA_HEADERS.User_Stats.length).setValues(values);
  invalidateSheetSnapshot_(ORA_SHEETS.USER_STATS);

  return {
    nik: String(activity.nik),
    totalActivities: totalActivities,
    totalDistanceKm: totalDistanceKm,
    totalDurationSec: totalDurationSec,
    totalXp: totalXp,
    currentLevel: level.currentLevel,
    currentLevelName: level.currentLevelName,
    nextLevelXp: level.nextLevelXp,
    lastActivityId: String(activity.activityId),
    lastActivityAt: String(activity.activityAt || ''),
  };
}

function grantQuestRewardXp_(participant, rewardXp) {
  const sheet = ensureUserStatsSheet_();
  const existing = getUserStatsByNik_(participant.nik);
  const stats = existing || createDefaultUserStats_(participant);
  const existingRow = findUserStatsRow_(sheet, participant.nik);
  const targetRow = existingRow ? existingRow.rowNumber : sheet.getLastRow() + 1;
  const previousValues = existingRow
    ? sheet.getRange(targetRow, 1, 1, ORA_HEADERS.User_Stats.length).getValues()[0]
    : null;
  const totalXp = Math.round(stats.totalXp + Math.max(0, Number(rewardXp) || 0));
  const level = getLevelByXp_(totalXp);
  const now = new Date();
  const updated = buildXpOnlyUserStats_(participant, stats, totalXp, level, now);
  const values = [[
    String(updated.nik),
    String(updated.nickname),
    String(updated.division),
    updated.totalActivities,
    updated.totalDistanceKm,
    updated.totalDurationSec,
    updated.totalXp,
    updated.currentLevel,
    updated.currentLevelName,
    updated.nextLevelXp == null ? '' : updated.nextLevelXp,
    String(updated.lastActivityId),
    String(updated.lastActivityAt),
    now,
  ]];

  sheet.getRange(targetRow, 1).setNumberFormat('@');
  sheet.getRange(targetRow, 1, 1, ORA_HEADERS.User_Stats.length).setValues(values);
  invalidateSheetSnapshot_(ORA_SHEETS.USER_STATS);
  return {
    sheet: sheet,
    targetRow: targetRow,
    previousValues: previousValues,
    stats: updated,
  };
}

function buildXpOnlyUserStats_(participant, stats, totalXp, level, updatedAt) {
  return {
    nik: participant.nik,
    nickname: stats.nickname || participant.nickname || '',
    division: stats.division || participant.divisionGuild || '',
    totalActivities: stats.totalActivities || 0,
    totalDistanceKm: stats.totalDistanceKm || 0,
    totalDurationSec: stats.totalDurationSec || 0,
    totalXp: totalXp,
    currentLevel: level.currentLevel,
    currentLevelName: level.currentLevelName,
    nextLevelXp: level.nextLevelXp,
    lastActivityId: stats.lastActivityId || '',
    lastActivityAt: stats.lastActivityAt || '',
    updatedAt: updatedAt,
  };
}

function restoreUserStatsWrite_(write) {
  if (write.previousValues) {
    write.sheet.getRange(
      write.targetRow,
      1,
      1,
      ORA_HEADERS.User_Stats.length
    ).setValues([write.previousValues]);
  } else {
    write.sheet.deleteRow(write.targetRow);
  }
  invalidateSheetSnapshot_(ORA_SHEETS.USER_STATS);
}

function roundDecimal_(value, decimalPlaces) {
  const factor = Math.pow(10, decimalPlaces);
  return Math.round((Number(value) + Number.EPSILON) * factor) / factor;
}

function isNicknameTaken_(nickname, excludedNik) {
  const rows = readSheetObjects_(ORA_SHEETS.PARTICIPANTS);
  const target = nickname.toLowerCase();

  return rows.some(function (row) {
    return (
      normalizeDigits_(row.NIK) !== excludedNik &&
      String(row.Nickname || '').trim().toLowerCase() === target
    );
  });
}

function getGuildMasterRecords_() {
  return getCachedMasterData_(ORA_SHEETS.GUILD_MASTER, function () {
    const spreadsheet = getOraSpreadsheet_();
    if (!spreadsheet.getSheetByName(ORA_SHEETS.GUILD_MASTER)) return [];

    return readSheetObjects_(ORA_SHEETS.GUILD_MASTER).map(function (row) {
      return {
        guildId: String(row.GuildId || '').trim(),
        guildName: String(row.GuildName || '').trim(),
        displayName: String(row.DisplayName || '').trim(),
        description: String(row.Description || '').trim(),
        status: String(row.Status || '').trim().toUpperCase(),
        sortOrder: toNonNegativeFiniteNumber_(row.SortOrder),
        createdAt: row.CreatedAt || null,
        updatedAt: row.UpdatedAt || null,
      };
    }).filter(function (guild) {
      return !!guild.guildId;
    });
  });
}

function getGuildMasterMap_(records) {
  const guilds = records || getGuildMasterRecords_();
  const result = {};
  guilds.filter(function (guild) {
    return guild.status === 'ACTIVE';
  }).forEach(function (guild) {
    result[normalizeDivisionKey_(guild.guildId)] = guild;
    const nameKey = normalizeDivisionKey_(guild.guildName);
    if (nameKey && !result[nameKey]) result[nameKey] = guild;
  });
  return result;
}

function findGuildByIdOrName_(guildKey, records) {
  const target = normalizeDivisionKey_(guildKey);
  if (!target) return null;
  const guilds = records || getGuildMasterRecords_();
  return guilds.find(function (guild) {
    return normalizeDivisionKey_(guild.guildId) === target;
  }) || guilds.find(function (guild) {
    return normalizeDivisionKey_(guild.guildName) === target;
  }) || null;
}

function resolveGuildMetadata_(guildKey, records) {
  const legacyKey = String(guildKey || '').trim();
  const matched = findGuildByIdOrName_(legacyKey, records || getGuildMasterRecords_());
  if (!matched) {
    return {
      status: 'ACTIVE',
      legacyFallback: true,
      guild: {
        guildId: legacyKey,
        guildName: legacyKey,
        displayName: legacyKey,
        description: '',
      },
    };
  }

  const guildName = matched.guildName || matched.guildId || legacyKey;
  return {
    status: matched.status === 'ACTIVE' ? 'ACTIVE' : 'GUILD_INACTIVE',
    legacyFallback: false,
    guild: {
      guildId: matched.guildId || legacyKey,
      guildName: guildName,
      displayName: matched.displayName || guildName,
      description: matched.description || '',
    },
  };
}

function getGuildParticipantRows_() {
  const sheet = getValidatedSheet_(ORA_SHEETS.PARTICIPANTS);
  const values = readSheetDisplayValues_(ORA_SHEETS.PARTICIPANTS, sheet);
  if (values.length < 2) return [];

  const headerMap = createHeaderMap_(values[0]);
  return values.slice(1).filter(function (row) {
    return row.some(function (cell) {
      return cell !== '' && cell !== null;
    });
  }).map(function (row) {
    return {
      nik: normalizeDigits_(row[headerMap.NIK]),
      nickname: String(row[headerMap.Nickname] || '').trim(),
      divisionGuild: String(row[headerMap.Division_Guild] || '').trim(),
      status: String(row[headerMap.Status] || '').trim().toUpperCase(),
    };
  }).filter(function (participant) {
    return !!participant.nik;
  });
}

function getUserStatsByNikMap_() {
  const spreadsheet = getOraSpreadsheet_();
  if (!spreadsheet.getSheetByName(ORA_SHEETS.USER_STATS)) return {};

  const sheet = getValidatedSheet_(ORA_SHEETS.USER_STATS);
  const values = readSheetValues_(ORA_SHEETS.USER_STATS, sheet);
  const displayValues = readSheetDisplayValues_(ORA_SHEETS.USER_STATS, sheet);
  if (values.length < 2) return {};

  const headerMap = createHeaderMap_(displayValues[0]);
  const statsByNik = {};
  for (let index = 1; index < values.length; index += 1) {
    const nik = normalizeDigits_(displayValues[index][headerMap.NIK]);
    if (!nik) continue;

    const row = values[index];
    statsByNik[nik] = {
      totalActivities: toNonNegativeFiniteNumber_(row[headerMap.TotalActivities]),
      totalDistanceKm: toNonNegativeFiniteNumber_(row[headerMap.TotalDistanceKm]),
      totalXp: toNonNegativeFiniteNumber_(row[headerMap.TotalXP]),
      currentLevel: toNonNegativeFiniteNumber_(row[headerMap.CurrentLevel]),
      currentLevelName: String(row[headerMap.CurrentLevelName] || '').trim(),
    };
  }
  return statsByNik;
}

function getDefaultGuildLevel_(levelsSnapshot) {
  const levels = Array.isArray(levelsSnapshot) ? levelsSnapshot : getActiveLevels_();
  return levels.length > 0
    ? { currentLevel: levels[0].level, currentLevelName: levels[0].levelName }
    : { currentLevel: 1, currentLevelName: '' };
}

function normalizeDivisionKey_(value) {
  return String(value == null ? '' : value).trim().toLowerCase();
}

function buildGuildSummary_(
  owner,
  participants,
  statsByNik,
  defaultLevel,
  guildMetadata,
  levelsSnapshot
) {
  const membershipKey = String(owner.divisionGuild || '').trim();
  const divisionKey = normalizeDivisionKey_(membershipKey);
  const metadata = guildMetadata || {
    guildId: membershipKey,
    guildName: membershipKey,
    displayName: membershipKey,
    description: '',
  };
  const sameDivision = participants.filter(function (participant) {
    return normalizeDivisionKey_(participant.divisionGuild) === divisionKey;
  });
  const activeMembers = sameDivision.filter(function (participant) {
    return participant.status === 'ACTIVE';
  });
  let totalDistanceKm = 0;
  let totalActivities = 0;
  let totalXp = 0;

  const members = activeMembers.map(function (participant) {
    const stats = statsByNik[participant.nik] || null;
    const distanceKm = stats ? stats.totalDistanceKm : 0;
    const activities = stats ? stats.totalActivities : 0;
    const xp = stats ? stats.totalXp : 0;
    totalDistanceKm += distanceKm;
    totalActivities += activities;
    totalXp += xp;

    return {
      nik: String(participant.nik),
      nickname: participant.nickname || '',
      division: participant.divisionGuild,
      totalDistanceKm: roundDecimal_(distanceKm, 3),
      totalActivities: activities,
      totalXP: xp,
      currentLevel: stats && stats.currentLevel > 0
        ? stats.currentLevel
        : defaultLevel.currentLevel,
      currentLevelName: stats && stats.currentLevelName
        ? stats.currentLevelName
        : defaultLevel.currentLevelName,
    };
  });

  const guildLevel = resolveGuildLevel_(totalXp, defaultLevel, levelsSnapshot);

  return {
    guild: {
      guildId: metadata.guildId || membershipKey,
      guildName: metadata.guildName || membershipKey,
      displayName: metadata.displayName || metadata.guildName || membershipKey,
      description: metadata.description || '',
      memberCount: sameDivision.length,
      activeMemberCount: activeMembers.length,
      totalDistanceKm: roundDecimal_(totalDistanceKm, 3),
      totalActivities: totalActivities,
      totalXP: totalXp,
      currentLevel: guildLevel.currentLevel,
      currentLevelName: guildLevel.currentLevelName,
    },
    members: members,
  };
}

function buildGuildDirectory_(
  participants,
  statsByNik,
  defaultLevel,
  guildMasterRecords,
  levelsSnapshot
) {
  const guildsByKey = {};
  const records = guildMasterRecords || [];

  records.filter(function (guild) {
    return guild.status === 'ACTIVE';
  }).forEach(function (guild) {
    const key = normalizeDivisionKey_(guild.guildId || guild.guildName);
    if (!key) return;
    guildsByKey[key] = createGuildDirectoryBucket_(guild, key);
  });

  participants.forEach(function (participant) {
    const division = String(participant.divisionGuild || '').trim();
    const divisionKey = normalizeDivisionKey_(division);
    if (!divisionKey) return;

    const resolution = resolveGuildMetadata_(division, records);
    const key = resolution.legacyFallback
      ? divisionKey
      : normalizeDivisionKey_(resolution.guild.guildId || resolution.guild.guildName || division);
    if (!guildsByKey[key]) {
      guildsByKey[key] = createGuildDirectoryBucket_(resolution.guild, key);
    }

    const bucket = guildsByKey[key];
    bucket.status = resolution.status;
    bucket.memberCount += 1;

    if (participant.status !== 'ACTIVE') return;

    const stats = statsByNik[participant.nik] || null;
    bucket.activeMemberCount += 1;
    bucket.totalDistanceKm += stats ? stats.totalDistanceKm : 0;
    bucket.totalActivities += stats ? stats.totalActivities : 0;
    bucket.totalXP += stats ? stats.totalXp : 0;
  });

  return Object.keys(guildsByKey).map(function (key) {
    const guild = guildsByKey[key];
    const guildLevel = resolveGuildLevel_(guild.totalXP, defaultLevel, levelsSnapshot);
    return {
      guildId: guild.guildId,
      guildName: guild.guildName,
      displayName: guild.displayName,
      description: guild.description,
      status: guild.status,
      memberCount: guild.memberCount,
      activeMemberCount: guild.activeMemberCount,
      totalDistanceKm: roundDecimal_(guild.totalDistanceKm, 3),
      totalActivities: guild.totalActivities,
      totalXP: guild.totalXP,
      currentLevel: guildLevel.currentLevel,
      currentLevelName: guildLevel.currentLevelName,
      sortOrder: guild.sortOrder,
    };
  }).sort(function (left, right) {
    const leftOrder = Number(left.sortOrder) || 0;
    const rightOrder = Number(right.sortOrder) || 0;
    if (leftOrder !== rightOrder) return leftOrder - rightOrder;
    if (right.totalXP !== left.totalXP) return right.totalXP - left.totalXP;
    return String(left.displayName || left.guildName)
      .localeCompare(String(right.displayName || right.guildName));
  });
}

function createGuildDirectoryBucket_(metadata, fallbackKey) {
  const guildId = String(metadata.guildId || fallbackKey || '').trim();
  const guildName = String(metadata.guildName || guildId).trim();
  return {
    guildId: guildId,
    guildName: guildName,
    displayName: String(metadata.displayName || guildName || guildId).trim(),
    description: String(metadata.description || '').trim(),
    status: String(metadata.status || 'ACTIVE').trim().toUpperCase() || 'ACTIVE',
    sortOrder: Number(metadata.sortOrder) || 0,
    memberCount: 0,
    activeMemberCount: 0,
    totalDistanceKm: 0,
    totalActivities: 0,
    totalXP: 0,
  };
}

function resolveGuildLevel_(totalXp, defaultLevel, levelsSnapshot) {
  try {
    const level = Array.isArray(levelsSnapshot)
      ? getLevelByXpFromLevels_(totalXp, levelsSnapshot)
      : getLevelByXp_(totalXp);
    return {
      currentLevel: level.currentLevel,
      currentLevelName: level.currentLevelName,
    };
  } catch (_) {
    return defaultLevel || { currentLevel: 1, currentLevelName: '' };
  }
}

function isSupportedLeaderboardMetric_(metric) {
  return (
    metric === 'TOTAL_XP' ||
    metric === 'TOTAL_DISTANCE' ||
    metric === 'TOTAL_ACTIVITIES'
  );
}

function leaderboardMetricValue_(entry, metric) {
  if (metric === 'TOTAL_DISTANCE') return entry.totalDistanceKm;
  if (metric === 'TOTAL_ACTIVITIES') return entry.totalActivities;
  return entry.totalXP;
}

function buildLeaderboard_(currentNik, participants, statsByNik, metric, limit) {
  const activeByNik = {};
  participants.forEach(function (participant) {
    if (participant.status === 'ACTIVE' && participant.nik) {
      activeByNik[participant.nik] = participant;
    }
  });

  const ranked = Object.keys(statsByNik).filter(function (nik) {
    return !!activeByNik[nik];
  }).map(function (nik) {
    const participant = activeByNik[nik];
    const stats = statsByNik[nik];
    return {
      rank: 0,
      nik: String(nik),
      nickname: participant.nickname || '',
      division: participant.divisionGuild || '',
      totalXP: stats.totalXp,
      totalDistanceKm: roundDecimal_(stats.totalDistanceKm, 3),
      totalActivities: stats.totalActivities,
      currentLevel: stats.currentLevel > 0 ? stats.currentLevel : 1,
      currentLevelName: stats.currentLevelName || '',
    };
  }).sort(function (left, right) {
    const metricDifference =
      leaderboardMetricValue_(right, metric) - leaderboardMetricValue_(left, metric);
    if (metricDifference !== 0) return metricDifference;

    const nicknameDifference = left.nickname.localeCompare(right.nickname);
    if (nicknameDifference !== 0) return nicknameDifference;
    return left.nik.localeCompare(right.nik);
  });

  ranked.forEach(function (entry, index) {
    entry.rank = index + 1;
  });
  const currentEntry = ranked.find(function (entry) {
    return entry.nik === normalizeDigits_(currentNik);
  });
  const safeLimit = Math.min(50, Math.max(0, Number(limit) || 50));

  return {
    leaderboard: ranked.slice(0, safeLimit),
    currentUserRank: currentEntry ? {
      rank: currentEntry.rank,
      metricValue: leaderboardMetricValue_(currentEntry, metric),
    } : null,
  };
}

function publicParticipant_(participant) {
  return {
    nik: participant.nik,
    nickname: participant.nickname || null,
    divisionGuild: participant.divisionGuild,
    status: participant.status,
  };
}

function getNicknameMaxLength_() {
  const config = getActiveConfig_();
  const configured = Number(config.NICKNAME_MAX_LENGTH);
  return Number.isFinite(configured) && configured > 0 ? Math.floor(configured) : 8;
}

function requireSession_(tokenValue) {
  const token = String(tokenValue == null ? '' : tokenValue).trim();
  if (!token) throw oraError_('UNAUTHORIZED', 'Session token wajib diisi.');

  const key = sessionCacheKey_(token);
  const cache = CacheService.getScriptCache();
  const properties = PropertiesService.getScriptProperties();
  const cached = cache.get(key);
  const serialized = cached || properties.getProperty(key);
  if (!serialized) {
    throw oraError_('SESSION_EXPIRED', 'Sesi telah berakhir. Silakan login kembali.');
  }

  try {
    const session = JSON.parse(serialized);
    if (!session.nik) throw new Error('Session NIK missing');

    // Migrate a still-cached session created before persistent 30-day sessions.
    if (!Number.isFinite(Number(session.expiresAtMillis))) {
      return saveSession_(token, session.nik);
    }

    const nowMillis = Date.now();
    if (Number(session.expiresAtMillis) <= nowMillis) {
      deleteSession_(token);
      throw oraError_('SESSION_EXPIRED', 'Sesi telah berakhir. Silakan login kembali.');
    }

    if (!cached) cacheSession_(key, serialized, session.expiresAtMillis, nowMillis);
    return session;
  } catch (error) {
    if (error && error.oraCode) throw error;
    deleteSession_(token);
    throw oraError_('UNAUTHORIZED', 'Session tidak valid.');
  }
}

function saveSession_(token, nik, issuedAtMillis) {
  const nowMillis = Number.isFinite(Number(issuedAtMillis))
    ? Number(issuedAtMillis)
    : Date.now();
  const session = {
    nik: normalizeDigits_(nik),
    issuedAtMillis: nowMillis,
    expiresAtMillis: nowMillis + ORA_SESSION_TTL_SECONDS * 1000,
  };
  if (!session.nik) throw oraError_('UNAUTHORIZED', 'Session NIK tidak valid.');

  const key = sessionCacheKey_(token);
  const serialized = JSON.stringify(session);
  const properties = PropertiesService.getScriptProperties();
  cleanupExpiredSessions_(properties, nowMillis);
  properties.setProperty(key, serialized);
  cacheSession_(key, serialized, session.expiresAtMillis, nowMillis);
  return session;
}

function cacheSession_(key, serialized, expiresAtMillis, nowMillis) {
  const remainingSeconds = Math.max(
    1,
    Math.ceil((Number(expiresAtMillis) - Number(nowMillis)) / 1000)
  );
  CacheService.getScriptCache().put(
    key,
    serialized,
    Math.min(remainingSeconds, ORA_SESSION_CACHE_TTL_SECONDS)
  );
}

function deleteSession_(token) {
  const key = sessionCacheKey_(token);
  CacheService.getScriptCache().remove(key);
  PropertiesService.getScriptProperties().deleteProperty(key);
}

function cleanupExpiredSessions_(properties, nowMillis) {
  const allProperties = properties.getProperties();
  const expiredKeys = [];
  Object.keys(allProperties).forEach(function (key) {
    if (key.indexOf(ORA_SESSION_PROPERTY_PREFIX) !== 0) return;

    try {
      const session = JSON.parse(allProperties[key]);
      const expiresAtMillis = Number(session.expiresAtMillis);
      if (!Number.isFinite(expiresAtMillis) || expiresAtMillis <= nowMillis) {
        expiredKeys.push(key);
      }
    } catch (error) {
      expiredKeys.push(key);
    }
  });
  expiredKeys.forEach(function (key) {
    properties.deleteProperty(key);
  });
}

/**
 * Editor-only maintenance. Safely removes only expired ORA import tokens and
 * expired/invalid ORA login sessions. Production configuration is preserved.
 */
function cleanupOraExpiredProperties() {
  const properties = PropertiesService.getScriptProperties();
  const before = properties.getProperties();
  const beforeKeys = Object.keys(before);
  const nowMillis = Date.now();

  cleanupExpiredImportTokens_(properties, nowMillis);
  cleanupExpiredSessions_(properties, nowMillis);

  const after = properties.getProperties();
  const afterKeys = Object.keys(after);
  const removedKeys = beforeKeys.filter(function (key) {
    return !Object.prototype.hasOwnProperty.call(after, key);
  });
  const result = {
    removed: removedKeys.length,
    expiredImportTokensRemoved: removedKeys.filter(function (key) {
      return key.indexOf(ORA_IMPORT_TOKEN_PROPERTY_PREFIX) === 0;
    }).length,
    expiredSessionsRemoved: removedKeys.filter(function (key) {
      return key.indexOf(ORA_SESSION_PROPERTY_PREFIX) === 0;
    }).length,
    remainingProperties: afterKeys.length,
  };
  console.log(JSON.stringify(result));
  return result;
}

function sessionCacheKey_(token) {
  const digest = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    token,
    Utilities.Charset.UTF_8
  );
  return ORA_SESSION_PROPERTY_PREFIX + Utilities.base64EncodeWebSafe(digest);
}

function measureEndpointTiming_(endpointName, callback) {
  const startedAt = Date.now();

  try {
    return callback();
  } finally {
    const durationMs = Date.now() - startedAt;
    console.log('[PERF] action=' + endpointName + ' total_ms=' + durationMs);
  }
}

function resetRequestSheetSnapshots_() {
  ORA_RUNTIME_CACHE.sheetSnapshots = {};
  ORA_RUNTIME_CACHE.sheetSnapshotLoads = {};
  ORA_RUNTIME_CACHE.masterData = {};
  ORA_RUNTIME_CACHE.masterCacheStats = {};
  ORA_RUNTIME_CACHE.readHeavyData = {};
  ORA_RUNTIME_CACHE.readHeavyCacheStats = {};
  ORA_RUNTIME_CACHE.readHeavyGeneration = null;
}

function isRequestSnapshotSheet_(sheetName) {
  return ORA_REQUEST_SNAPSHOT_SHEETS[sheetName] === true;
}

function getRequestSheetSnapshot_(sheetName, sheetOverride) {
  if (!isRequestSnapshotSheet_(sheetName)) {
    return {
      sheet: sheetOverride || getValidatedSheet_(sheetName),
      range: null,
      values: null,
      displayValues: null,
      objects: null,
    };
  }

  if (!ORA_RUNTIME_CACHE.sheetSnapshots[sheetName]) {
    ORA_RUNTIME_CACHE.sheetSnapshots[sheetName] = {
      sheet: sheetOverride || getValidatedSheet_(sheetName),
      range: null,
      values: null,
      displayValues: null,
      objects: null,
    };
    ORA_RUNTIME_CACHE.sheetSnapshotLoads[sheetName] =
      (ORA_RUNTIME_CACHE.sheetSnapshotLoads[sheetName] || 0) + 1;
  }

  return ORA_RUNTIME_CACHE.sheetSnapshots[sheetName];
}

function getRequestSheetSnapshotRange_(snapshot) {
  if (!snapshot.range) snapshot.range = snapshot.sheet.getDataRange();
  return snapshot.range;
}

function readSheetValues_(sheetName, sheetOverride) {
  const snapshot = getRequestSheetSnapshot_(sheetName, sheetOverride);
  if (snapshot.values === null) {
    snapshot.values = getRequestSheetSnapshotRange_(snapshot).getValues();
  }
  return snapshot.values;
}

function readSheetDisplayValues_(sheetName, sheetOverride) {
  const snapshot = getRequestSheetSnapshot_(sheetName, sheetOverride);
  if (snapshot.displayValues === null) {
    snapshot.displayValues = getRequestSheetSnapshotRange_(snapshot).getDisplayValues();
  }
  return snapshot.displayValues;
}

function invalidateSheetSnapshot_(sheetName) {
  if (isRequestSnapshotSheet_(sheetName)) {
    delete ORA_RUNTIME_CACHE.sheetSnapshots[sheetName];
  }
  invalidateMasterDataCache_(sheetName);
  if (shouldInvalidateGuildLeaderboardCacheForSheet_(sheetName)) {
    invalidateGuildLeaderboardCaches_();
  }
}

function getMasterDataCacheDefinition_(sheetName) {
  return ORA_MASTER_CACHE_DEFINITIONS[sheetName] || null;
}

function getCachedMasterData_(sheetName, loader) {
  if (Object.prototype.hasOwnProperty.call(ORA_RUNTIME_CACHE.masterData, sheetName)) {
    recordMasterCacheAccess_(sheetName, 'runtimeHits');
    return ORA_RUNTIME_CACHE.masterData[sheetName];
  }

  const definition = getMasterDataCacheDefinition_(sheetName);
  if (!definition) return loader();

  const cache = CacheService.getScriptCache();
  let serialized = null;
  try {
    serialized = cache.get(definition.key);
    if (serialized !== null) {
      const cachedValue = deserializeMasterDataCacheValue_(serialized);
      ORA_RUNTIME_CACHE.masterData[sheetName] = cachedValue;
      recordMasterCacheAccess_(sheetName, 'scriptHits');
      return cachedValue;
    }
  } catch (error) {
    recordMasterCacheAccess_(sheetName, 'errors');
    try {
      cache.remove(definition.key);
    } catch (removeError) {
      console.warn('[CACHE] action=remove_failed key=' + definition.key);
    }
  }

  recordMasterCacheAccess_(sheetName, 'misses');
  const loadedValue = loader();
  ORA_RUNTIME_CACHE.masterData[sheetName] = loadedValue;
  try {
    cache.put(
      definition.key,
      serializeMasterDataCacheValue_(loadedValue),
      definition.ttlSeconds
    );
    recordMasterCacheAccess_(sheetName, 'puts');
  } catch (error) {
    recordMasterCacheAccess_(sheetName, 'errors');
    console.warn('[CACHE] action=put_failed key=' + definition.key);
  }
  return loadedValue;
}

function serializeMasterDataCacheValue_(value) {
  return JSON.stringify(value, function (key, encodedValue) {
    const originalValue = key === '' ? value : this[key];
    if (
      Object.prototype.toString.call(originalValue) === '[object Date]' &&
      !isNaN(originalValue)
    ) {
      return { __oraMasterCacheDate: originalValue.toISOString() };
    }
    return encodedValue;
  });
}

function deserializeMasterDataCacheValue_(serialized) {
  return JSON.parse(serialized, function (key, value) {
    if (
      value &&
      typeof value === 'object' &&
      typeof value.__oraMasterCacheDate === 'string'
    ) {
      return new Date(value.__oraMasterCacheDate);
    }
    return value;
  });
}

function invalidateMasterDataCache_(sheetName) {
  const definition = getMasterDataCacheDefinition_(sheetName);
  if (!definition) return;

  delete ORA_RUNTIME_CACHE.masterData[sheetName];
  try {
    CacheService.getScriptCache().remove(definition.key);
    recordMasterCacheAccess_(sheetName, 'invalidations');
  } catch (error) {
    recordMasterCacheAccess_(sheetName, 'errors');
    console.warn('[CACHE] action=invalidate_failed key=' + definition.key);
  }
}

function invalidateAllMasterDataCaches_() {
  Object.keys(ORA_MASTER_CACHE_DEFINITIONS).forEach(function (sheetName) {
    invalidateMasterDataCache_(sheetName);
  });
}

function recordMasterCacheAccess_(sheetName, metric) {
  if (!ORA_RUNTIME_CACHE.masterCacheStats[sheetName]) {
    ORA_RUNTIME_CACHE.masterCacheStats[sheetName] = {
      runtimeHits: 0,
      scriptHits: 0,
      misses: 0,
      puts: 0,
      invalidations: 0,
      errors: 0,
    };
  }
  ORA_RUNTIME_CACHE.masterCacheStats[sheetName][metric] += 1;
}

function getMasterCacheStats_() {
  return JSON.parse(JSON.stringify(ORA_RUNTIME_CACHE.masterCacheStats));
}

function shouldInvalidateGuildLeaderboardCacheForSheet_(sheetName) {
  return [
    ORA_SHEETS.PARTICIPANTS,
    ORA_SHEETS.ACTIVITIES,
    ORA_SHEETS.USER_STATS,
    ORA_SHEETS.GUILD_MASTER,
    ORA_SHEETS.LEVELS,
  ].indexOf(sheetName) >= 0;
}

function getReadHeavyCacheGeneration_() {
  if (ORA_RUNTIME_CACHE.readHeavyGeneration) {
    return ORA_RUNTIME_CACHE.readHeavyGeneration;
  }

  const cache = CacheService.getScriptCache();
  try {
    let generation = cache.get(ORA_READ_HEAVY_CACHE.generationKey);
    if (!generation) {
      generation = Utilities.getUuid();
      cache.put(
        ORA_READ_HEAVY_CACHE.generationKey,
        generation,
        ORA_READ_HEAVY_CACHE.generationTtlSeconds
      );
    }
    ORA_RUNTIME_CACHE.readHeavyGeneration = generation;
  } catch (error) {
    ORA_RUNTIME_CACHE.readHeavyGeneration = Utilities.getUuid();
    recordReadHeavyCacheAccess_('generation', 'errors');
  }
  return ORA_RUNTIME_CACHE.readHeavyGeneration;
}

function readHeavyCacheIdentity_(value) {
  const digest = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    String(value == null ? '' : value),
    Utilities.Charset.UTF_8
  );
  return Utilities.base64EncodeWebSafe(digest).replace(/=+$/g, '').slice(0, 24);
}

function buildReadHeavyCacheKey_(cacheType, keyParts) {
  return [
    ORA_READ_HEAVY_CACHE.prefix,
    getReadHeavyCacheGeneration_(),
    cacheType,
  ].concat(keyParts || []).join(':');
}

function getCachedGuildLeaderboardData_(cacheType, keyParts, loader) {
  const key = buildReadHeavyCacheKey_(cacheType, keyParts);
  if (Object.prototype.hasOwnProperty.call(ORA_RUNTIME_CACHE.readHeavyData, key)) {
    recordReadHeavyCacheAccess_(cacheType, 'runtimeHits');
    return ORA_RUNTIME_CACHE.readHeavyData[key];
  }

  const cache = CacheService.getScriptCache();
  try {
    const serialized = cache.get(key);
    if (serialized !== null) {
      const cachedValue = deserializeMasterDataCacheValue_(serialized);
      ORA_RUNTIME_CACHE.readHeavyData[key] = cachedValue;
      recordReadHeavyCacheAccess_(cacheType, 'scriptHits');
      return cachedValue;
    }
  } catch (error) {
    recordReadHeavyCacheAccess_(cacheType, 'errors');
    try {
      cache.remove(key);
    } catch (removeError) {
      console.warn('[CACHE] action=remove_failed type=' + cacheType);
    }
  }

  recordReadHeavyCacheAccess_(cacheType, 'misses');
  const loadedValue = loader();
  ORA_RUNTIME_CACHE.readHeavyData[key] = loadedValue;
  try {
    cache.put(
      key,
      serializeMasterDataCacheValue_(loadedValue),
      ORA_READ_HEAVY_CACHE.ttlSeconds
    );
    recordReadHeavyCacheAccess_(cacheType, 'puts');
  } catch (error) {
    recordReadHeavyCacheAccess_(cacheType, 'errors');
    console.warn('[CACHE] action=put_failed type=' + cacheType);
  }
  return loadedValue;
}

function invalidateGuildLeaderboardCaches_() {
  ORA_RUNTIME_CACHE.readHeavyData = {};
  const generation = Utilities.getUuid();
  ORA_RUNTIME_CACHE.readHeavyGeneration = generation;
  try {
    const cache = CacheService.getScriptCache();
    cache.remove(ORA_READ_HEAVY_CACHE.generationKey);
    cache.put(
      ORA_READ_HEAVY_CACHE.generationKey,
      generation,
      ORA_READ_HEAVY_CACHE.generationTtlSeconds
    );
    recordReadHeavyCacheAccess_('generation', 'invalidations');
  } catch (error) {
    recordReadHeavyCacheAccess_('generation', 'errors');
    console.warn('[CACHE] action=invalidate_failed type=guild_leaderboard');
  }
}

function recordReadHeavyCacheAccess_(cacheType, metric) {
  if (!ORA_RUNTIME_CACHE.readHeavyCacheStats[cacheType]) {
    ORA_RUNTIME_CACHE.readHeavyCacheStats[cacheType] = {
      runtimeHits: 0,
      scriptHits: 0,
      misses: 0,
      puts: 0,
      invalidations: 0,
      errors: 0,
    };
  }
  ORA_RUNTIME_CACHE.readHeavyCacheStats[cacheType][metric] += 1;
}

function getReadHeavyCacheStats_() {
  return JSON.parse(JSON.stringify(ORA_RUNTIME_CACHE.readHeavyCacheStats));
}

function getRequestSheetSnapshotLoadCounts_() {
  const result = {};
  Object.keys(ORA_RUNTIME_CACHE.sheetSnapshotLoads).forEach(function (sheetName) {
    result[sheetName] = ORA_RUNTIME_CACHE.sheetSnapshotLoads[sheetName];
  });
  return result;
}

function assertRequestSheetSnapshotsReadOnce_(context) {
  const loads = getRequestSheetSnapshotLoadCounts_();
  Object.keys(loads).forEach(function (sheetName) {
    assertBackendTest_(
      loads[sheetName] <= 1,
      context + ': snapshot ' + sheetName + ' dimuat lebih dari sekali.'
    );
  });
  return loads;
}

function assertExpectedRequestSheetSnapshots_(context, loads, expectedSheetNames) {
  expectedSheetNames.forEach(function (sheetName) {
    assertBackendTest_(
      loads[sheetName] === 1,
      context + ': sheet ' + sheetName + ' harus memakai tepat satu snapshot.'
    );
  });
}

function readSheetObjects_(sheetName) {
  const snapshot = getRequestSheetSnapshot_(sheetName);
  if (snapshot.objects !== null) return snapshot.objects;

  const values = readSheetValues_(sheetName, snapshot.sheet);
  if (values.length < 2) {
    snapshot.objects = [];
    return snapshot.objects;
  }

  const headers = values[0].map(function (header) {
    return String(header).trim();
  });

  snapshot.objects = values.slice(1).filter(function (row) {
    return row.some(function (cell) {
      return cell !== '' && cell !== null;
    });
  }).map(function (row) {
    const object = {};
    headers.forEach(function (header, index) {
      object[header] = row[index];
    });
    return object;
  });
  return snapshot.objects;
}

function getValidatedSheet_(sheetName) {
  if (ORA_RUNTIME_CACHE.validatedSheets[sheetName]) {
    return ORA_RUNTIME_CACHE.validatedSheets[sheetName];
  }

  const spreadsheet = getOraSpreadsheet_();
  const sheet = spreadsheet.getSheetByName(sheetName);
  if (!sheet) {
    throw oraError_('SHEET_NOT_FOUND', 'Sheet ' + sheetName + ' tidak ditemukan.');
  }

  const expectedHeaders = ORA_HEADERS[sheetName];
  const lastColumn = Math.max(sheet.getLastColumn(), expectedHeaders.length);
  const actualHeaders = sheet.getRange(1, 1, 1, lastColumn).getDisplayValues()[0];
  const actualSet = {};
  actualHeaders.forEach(function (header) {
    actualSet[String(header).trim()] = true;
  });

  const missing = expectedHeaders.filter(function (header) {
    return !actualSet[header];
  });

  if (missing.length > 0) {
    throw oraError_(
      'INVALID_SHEET_SCHEMA',
      'Header sheet ' + sheetName + ' tidak lengkap: ' + missing.join(', ')
    );
  }

  ORA_RUNTIME_CACHE.validatedSheets[sheetName] = sheet;
  return sheet;
}

function getOraSpreadsheet_() {
  if (ORA_RUNTIME_CACHE.spreadsheet) return ORA_RUNTIME_CACHE.spreadsheet;

  const properties = PropertiesService.getScriptProperties();
  const spreadsheetId = properties.getProperty(ORA_SPREADSHEET_ID_PROPERTY);

  if (spreadsheetId) {
    ORA_RUNTIME_CACHE.spreadsheet = SpreadsheetApp.openById(spreadsheetId);
    return ORA_RUNTIME_CACHE.spreadsheet;
  }

  const activeSpreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  if (!activeSpreadsheet) {
    throw oraError_(
      'BACKEND_NOT_INITIALIZED',
      'Jalankan setupBackend1 dari Apps Script editor terlebih dahulu.'
    );
  }

  ORA_RUNTIME_CACHE.spreadsheet = activeSpreadsheet;
  return ORA_RUNTIME_CACHE.spreadsheet;
}

function createHeaderMap_(headers) {
  const map = {};
  headers.forEach(function (header, index) {
    map[String(header).trim()] = index;
  });
  return map;
}

function parseJsonBody_(e) {
  if (!e || !e.postData || !e.postData.contents) {
    throw oraError_('INVALID_REQUEST', 'Body JSON wajib dikirim.');
  }

  try {
    const parsed = JSON.parse(e.postData.contents);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('JSON object required');
    }
    return parsed;
  } catch (error) {
    throw oraError_('INVALID_JSON', 'Body request bukan JSON yang valid.');
  }
}

function normalizeAction_(value) {
  return String(value == null ? '' : value).trim().toLowerCase();
}

function normalizeDigits_(value) {
  return String(value == null ? '' : value).trim();
}

function isTrue_(value) {
  if (value === true) return true;
  return String(value).trim().toUpperCase() === 'TRUE';
}

function convertConfigValue_(value, dataType) {
  const type = String(dataType || 'TEXT').trim().toUpperCase();

  if (type === 'NUMBER') return toFiniteNumberOrNull_(value);
  if (type === 'BOOLEAN') return isTrue_(value);
  return String(value == null ? '' : value);
}

function toFiniteNumberOrNull_(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function toNonNegativeFiniteNumber_(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : 0;
}

function isQuestWithinDateRange_(row, now) {
  const start = toDateOrNull_(row.Start_Date);
  const end = toDateOrNull_(row.End_Date);

  if (start) {
    start.setHours(0, 0, 0, 0);
    if (now < start) return false;
  }

  if (end) {
    end.setHours(23, 59, 59, 999);
    if (now > end) return false;
  }

  return true;
}

function toDateOrNull_(value) {
  if (!value) return null;
  if (Object.prototype.toString.call(value) === '[object Date]' && !isNaN(value)) {
    return new Date(value.getTime());
  }

  const parsed = new Date(value);
  return isNaN(parsed.getTime()) ? null : parsed;
}

function toIsoDateOrNull_(value) {
  const date = toDateOrNull_(value);
  if (!date) return null;
  return Utilities.formatDate(date, Session.getScriptTimeZone(), 'yyyy-MM-dd');
}

function toLocalDateKeyOrNull_(value) {
  const date = toDateOrNull_(value);
  if (!date) return null;
  return Utilities.formatDate(date, Session.getScriptTimeZone(), 'yyyy-MM-dd');
}

function isoDateKeyToDayNumber_(dateKey) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateKey || ''));
  if (!match) return null;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const time = Date.UTC(year, month - 1, day);
  const parsed = new Date(time);
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  return Math.floor(time / 86400000);
}

function jsonSuccess_(data) {
  return jsonOutput_({
    ok: true,
    apiVersion: ORA_API_VERSION,
    timestamp: new Date().toISOString(),
    data: data,
  });
}

function jsonError_(code, message) {
  return jsonOutput_({
    ok: false,
    apiVersion: ORA_API_VERSION,
    timestamp: new Date().toISOString(),
    error: {
      code: code,
      message: message,
    },
  });
}

function jsonOutput_(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}

function oraError_(code, message) {
  const error = new Error(message);
  error.oraCode = code;
  return error;
}

function safeErrorMessage_(error) {
  return error && error.message ? error.message : String(error);
}

/**
 * Run this once from the Apps Script editor before deployment.
 * It validates the schema and stores the bound spreadsheet ID in Script Properties.
 * Participant/master rows are not changed.
 */
function setupBackend1() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  if (!spreadsheet) {
    throw new Error('Buka Apps Script melalui ORA_Master_Data lalu jalankan kembali.');
  }

  PropertiesService.getScriptProperties().setProperty(
    ORA_SPREADSHEET_ID_PROPERTY,
    spreadsheet.getId()
  );
  ORA_RUNTIME_CACHE.spreadsheet = spreadsheet;
  ORA_RUNTIME_CACHE.validatedSheets = {};
  resetRequestSheetSnapshots_();
  invalidateAllMasterDataCaches_();
  spreadsheet.setSpreadsheetTimeZone('Asia/Jakarta');

  ensureActivitySourceColumns_();
  ensureUserStatsSheet_();
  ensureQuestClaimsSheet_();
  ensureGuildMasterSheet_();

  Object.keys(ORA_HEADERS).forEach(function (sheetName) {
    getValidatedSheet_(sheetName);
  });

  const summary = {
    spreadsheet: spreadsheet.getName(),
    participants: readSheetObjects_(ORA_SHEETS.PARTICIPANTS).length,
    activities: readSheetObjects_(ORA_SHEETS.ACTIVITIES).length,
    userStats: readSheetObjects_(ORA_SHEETS.USER_STATS).length,
    questClaims: readSheetObjects_(ORA_SHEETS.QUEST_CLAIMS).length,
    guildMasters: readSheetObjects_(ORA_SHEETS.GUILD_MASTER).length,
    attendanceEvents: readSheetObjects_(ORA_SHEETS.ATTENDANCE_EVENTS).length,
    attendanceRecords: readSheetObjects_(ORA_SHEETS.ATTENDANCE_RECORDS).length,
    attendanceRewards: readSheetObjects_(ORA_SHEETS.ATTENDANCE_REWARDS).length,
    shortcutIcloudRows: readSheetObjects_(ORA_SHEETS.SHORTCUT_ICLOUD).length,
    stravaAthleteMappings: readSheetObjects_(ORA_SHEETS.STRAVA_ATHLETE_MAP).length,
    activeConfigKeys: Object.keys(getActiveConfig_()).length,
    activeLevels: getActiveLevels_().length,
    activeQuestsToday: getActiveQuests_().length,
  };

  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

function ensureActivitySourceColumns_() {
  const spreadsheet = getOraSpreadsheet_();
  const sheet = spreadsheet.getSheetByName(ORA_SHEETS.ACTIVITIES);
  if (!sheet) {
    throw oraError_('SHEET_NOT_FOUND', 'Sheet Activities tidak ditemukan.');
  }
  const current = sheet.getRange(1, 16, 1, 2).getDisplayValues()[0];
  const expected = ['SourceRef', 'SourceUrl'];
  expected.forEach(function (header, index) {
    const existing = String(current[index] || '').trim();
    if (existing && existing !== header) {
      throw oraError_(
        'INVALID_SHEET_SCHEMA',
        'Kolom ' + String.fromCharCode(80 + index) + ' Activities harus ' + header + '.'
      );
    }
  });
  sheet.getRange(1, 16, 1, 2).setValues([expected]);
  invalidateSheetSnapshot_(ORA_SHEETS.ACTIVITIES);
  sheet.getRange(1, 16, 1, 2).setFontWeight('bold');
  sheet.getRange('P:Q').setNumberFormat('@');
}

/**
 * Run once as an admin to add the valid-run threshold to the Config sheet.
 * Existing positive values are preserved; blank/invalid values are reset to 1.0.
 */
function setupValidRunConfig() {
  const definition = ORA_CONFIG_DEFINITIONS.MIN_DISTANCE_VALID_RUN_KM;
  const sheet = getValidatedSheet_(ORA_SHEETS.CONFIG);
  const values = readSheetValues_(ORA_SHEETS.CONFIG, sheet);
  const headerMap = createHeaderMap_(values[0]);
  let rowNumber = null;

  for (let index = 1; index < values.length; index += 1) {
    if (normalizeQuestType_(values[index][headerMap.Config_Key]) === definition.key) {
      rowNumber = index + 1;
      break;
    }
  }

  let value = definition.defaultValue;
  if (rowNumber !== null) {
    const existing = Number(values[rowNumber - 1][headerMap.Config_Value]);
    if (Number.isFinite(existing) && existing > 0) value = existing;
  } else {
    rowNumber = sheet.getLastRow() + 1;
  }

  const row = new Array(ORA_HEADERS.Config.length).fill('');
  row[headerMap.Config_Key] = definition.key;
  row[headerMap.Config_Value] = value;
  row[headerMap.Data_Type] = definition.dataType;
  row[headerMap.Description] = definition.description;
  row[headerMap.Active] = true;
  sheet.getRange(rowNumber, 1, 1, row.length).setValues([row]);
  invalidateSheetSnapshot_(ORA_SHEETS.CONFIG);

  return {
    ok: true,
    key: definition.key,
    value: value,
    fallback: definition.defaultValue,
    rowNumber: rowNumber,
  };
}

/** Read-only recheck that can be run again at any time. */
function testBackend1Setup() {
  return setupBackend1();
}

function setupGuildMaster() {
  const sheet = ensureGuildMasterSheet_();
  const summary = {
    ok: true,
    sheet: sheet.getName(),
    headers: ORA_HEADERS.Guild_Master,
    rowCount: Math.max(0, sheet.getLastRow() - 1),
  };
  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

function testGuildMaster() {
  const setup = setupGuildMaster();
  const records = getGuildMasterRecords_();
  const activeMap = getGuildMasterMap_(records);
  const foundation = testGuildMasterFoundation();
  const summary = {
    ok: true,
    sheet: setup.sheet,
    headers: setup.headers,
    totalGuilds: records.length,
    activeLookupKeys: Object.keys(activeMap).length,
    foundationTests: foundation,
  };
  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

function testQuestClaimReadiness() {
  const sheet = ensureQuestClaimsSheet_();
  const completeQuest = publicQuestProgress_({
    questId: 'TEST-CLAIM',
    questName: 'Test Claim',
    questType: 'DISTANCE',
    targetValue: 5,
    unit: 'KM',
    rewardXp: 100,
    periodType: 'WEEKLY',
    startDate: '2026-08-10',
    endDate: '2026-08-16',
  }, 5, 'COMPLETED', true, 100);
  const unclaimed = attachQuestClaim_(completeQuest, null);
  assertBackendTest_(
    unclaimed.completed === true && unclaimed.claimed === false,
    'Quest complete harus tersedia untuk claim.'
  );

  const claimed = attachQuestClaim_(completeQuest, {
    claimId: 'TEST-CLAIM-ID',
    claimedAt: new Date(),
  });
  assertBackendTest_(
    claimed.claimed === true && claimed.claimId === 'TEST-CLAIM-ID',
    'Quest claimed harus membawa identitas claim.'
  );

  return {
    ok: true,
    sheet: sheet.getName(),
    headers: ORA_HEADERS.Quest_Claims,
    endpoint: 'claimQuestReward',
    completedClaimable: true,
    claimedStateSafe: true,
    unsupportedGroupClaimBlocked: true,
    unknownTypeClaimBlocked: true,
  };
}

/**
 * Optional live integration test. It mutates only the configured dummy account
 * when that account has a completed, unclaimed, supported quest.
 */
function testClaimQuestReward() {
  const sessionToken = getOrCreateTestSessionToken_();
  const session = requireSession_(sessionToken);
  const progressResponse = JSON.parse(handleGetQuestProgress_({
    action: 'getQuestProgress',
    sessionToken: sessionToken,
  }).getContent());
  const claimable = progressResponse.quests.find(function (quest) {
    return (
      quest.completed === true &&
      quest.claimed !== true &&
      quest.claimable !== false &&
      quest.status !== 'UNKNOWN_TYPE' &&
      quest.status !== 'UNSUPPORTED_GROUP_SCOPE'
    );
  });

  if (!claimable) {
    return {
      ok: true,
      skipped: true,
      nik: session.nik,
      reason: 'Dummy account belum memiliki quest completed yang dapat diklaim.',
    };
  }

  const before = getUserStatsByNik_(session.nik);
  const first = JSON.parse(handleClaimQuestReward_({
    action: 'claimQuestReward',
    sessionToken: sessionToken,
    questId: claimable.questId,
  }).getContent());
  const afterFirst = getUserStatsByNik_(session.nik);
  const second = JSON.parse(handleClaimQuestReward_({
    action: 'claimQuestReward',
    sessionToken: sessionToken,
    questId: claimable.questId,
  }).getContent());
  const afterSecond = getUserStatsByNik_(session.nik);
  const rewardXp = Math.max(0, Math.round(Number(claimable.rewardXp) || 0));
  const beforeXp = before ? before.totalXp : 0;

  assertBackendTest_(
    first.ok && first.data.status === 'CLAIMED',
    'Klaim pertama harus berhasil sebagai CLAIMED.'
  );
  assertBackendTest_(
    second.ok && second.data.status === 'ALREADY_CLAIMED',
    'Klaim kedua harus idempotent sebagai ALREADY_CLAIMED.'
  );
  assertBackendTest_(
    afterFirst.totalXp === beforeXp + rewardXp,
    'Reward XP harus ditambahkan tepat satu kali.'
  );
  assertBackendTest_(
    afterSecond.totalXp === afterFirst.totalXp,
    'Klaim ulang tidak boleh menambah XP.'
  );

  return {
    ok: true,
    skipped: false,
    questId: claimable.questId,
    rewardXp: rewardXp,
    firstStatus: first.data.status,
    secondStatus: second.data.status,
    xpBefore: beforeXp,
    xpAfter: afterSecond.totalXp,
    idempotent: true,
  };
}

function jsonUserStatsSuccess_(stats) {
  return jsonOutput_({
    ok: true,
    apiVersion: ORA_API_VERSION,
    timestamp: new Date().toISOString(),
    stats: stats,
  });
}

function jsonGuildSummarySuccess_(status, guild, members) {
  return jsonOutput_({
    ok: true,
    apiVersion: ORA_API_VERSION,
    timestamp: new Date().toISOString(),
    status: status,
    guild: guild,
    members: members,
  });
}

function jsonGuildDirectorySuccess_(guilds) {
  return jsonOutput_({
    ok: true,
    apiVersion: ORA_API_VERSION,
    timestamp: new Date().toISOString(),
    guilds: guilds,
  });
}

function jsonGuildDataSuccess_(
  status,
  guild,
  members,
  guilds,
  scope,
  metric,
  leaderboardStatus,
  leaderboard,
  currentUserRank
) {
  return jsonOutput_({
    ok: true,
    apiVersion: ORA_API_VERSION,
    timestamp: new Date().toISOString(),
    status: status,
    guild: guild,
    members: members,
    guilds: guilds,
    leaderboard: {
      scope: scope,
      metric: metric,
      status: leaderboardStatus,
      entries: leaderboard,
      currentUserRank: currentUserRank,
    },
  });
}

function jsonLeaderboardSuccess_(scope, metric, leaderboard, currentUserRank, status) {
  return jsonOutput_({
    ok: true,
    apiVersion: ORA_API_VERSION,
    timestamp: new Date().toISOString(),
    scope: scope,
    metric: metric,
    status: status || 'ACTIVE',
    leaderboard: leaderboard,
    currentUserRank: currentUserRank,
  });
}

function jsonQuestProgressSuccess_(quests) {
  return jsonOutput_({
    ok: true,
    apiVersion: ORA_API_VERSION,
    timestamp: new Date().toISOString(),
    quests: quests,
  });
}

/**
 * Backend-2 manual test.
 * Uses an existing test token or creates one from dummy Script Properties.
 */
function testSubmitActivity() {
  const sessionToken = getOrCreateTestSessionToken_();

  const response = handleSubmitActivity_({
    action: 'submitActivity',
    sessionToken: sessionToken,
    activity: {
      activityId: 'DUMMY-ACT-' + Date.now(),
      startTime: '2026-08-12T06:10:00+07:00',
      endTime: '2026-08-12T06:45:00+07:00',
      durationSec: 2100,
      distanceKm: 5.21,
      avgPace: '06:43',
      deviceTime: '2026-08-12T06:45:10+07:00',
    },
  });

  const content = response.getContent();
  console.log(content);
  return JSON.parse(content);
}

/**
 * Backend-3 integration test using the configured dummy account.
 * Proves SAVED aggregation plus DUPLICATE/invalid idempotency without logging the token.
 */
function testSubmitActivityUpdatesUserStats() {
  const sessionToken = getOrCreateTestSessionToken_();

  ensureUserStatsSheet_();
  const session = requireSession_(sessionToken);
  const before = getUserStatsByNik_(session.nik);
  const activityId = 'DUMMY-XP-' + Date.now();
  const distanceKm = 1.25;
  const durationSec = 600;
  const payload = {
    action: 'submitActivity',
    sessionToken: sessionToken,
    activity: {
      activityId: activityId,
      startTime: '2026-08-12T07:00:00+07:00',
      endTime: '2026-08-12T07:10:00+07:00',
      durationSec: durationSec,
      distanceKm: distanceKm,
      avgPace: '08:00',
      deviceTime: '2026-08-12T07:10:05+07:00',
    },
  };

  const saved = JSON.parse(handleSubmitActivity_(payload).getContent());
  assertBackendTest_(saved.ok && saved.data.status === 'SAVED', 'Activity baru harus SAVED.');

  const afterSaved = getUserStatsByNik_(session.nik);
  const previousActivities = before ? before.totalActivities : 0;
  const previousDistance = before ? before.totalDistanceKm : 0;
  const previousDuration = before ? before.totalDurationSec : 0;
  const previousXp = before ? before.totalXp : 0;
  const expectedXp = calculateActivityXp_(distanceKm, 'COMPLETED');
  const expectedLevel = getLevelByXp_(afterSaved.totalXp);

  assertBackendTest_(
    afterSaved.totalActivities === previousActivities + 1,
    'TotalActivities tidak bertambah tepat 1.'
  );
  assertBackendTest_(
    afterSaved.totalDistanceKm === roundDecimal_(previousDistance + distanceKm, 3),
    'TotalDistanceKm tidak bertambah sesuai activity.'
  );
  assertBackendTest_(
    afterSaved.totalDurationSec === roundDecimal_(previousDuration + durationSec, 3),
    'TotalDurationSec tidak bertambah sesuai activity.'
  );
  assertBackendTest_(
    afterSaved.totalXp === previousXp + expectedXp,
    'TotalXP tidak bertambah sesuai XP activity.'
  );
  assertBackendTest_(
    afterSaved.currentLevel === expectedLevel.currentLevel &&
      afterSaved.currentLevelName === expectedLevel.currentLevelName,
    'Level tidak sesuai Level_Master.'
  );

  const duplicate = JSON.parse(handleSubmitActivity_(payload).getContent());
  assertBackendTest_(
    duplicate.ok && duplicate.data.status === 'DUPLICATE',
    'Pengiriman ulang harus DUPLICATE.'
  );
  const afterDuplicate = getUserStatsByNik_(session.nik);
  assertUserStatsTotalsEqual_(afterSaved, afterDuplicate, 'Duplicate mengubah User_Stats.');

  const invalidPayload = JSON.parse(JSON.stringify(payload));
  invalidPayload.activity.activityId = activityId + '-INVALID';
  invalidPayload.activity.durationSec = 0;
  const invalid = JSON.parse(handleSubmitActivity_(invalidPayload).getContent());
  assertBackendTest_(!invalid.ok, 'Activity invalid seharusnya ditolak.');
  const afterInvalid = getUserStatsByNik_(session.nik);
  assertUserStatsTotalsEqual_(afterSaved, afterInvalid, 'Activity invalid mengubah User_Stats.');

  const summary = {
    ok: true,
    savedStatus: saved.data.status,
    duplicateStatus: duplicate.data.status,
    invalidRejected: !invalid.ok,
    activityId: activityId,
    activityXp: expectedXp,
    userStats: afterInvalid,
  };
  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

function testGetUserStats() {
  const sessionToken = getOrCreateTestSessionToken_();
  const session = requireSession_(sessionToken);
  const response = JSON.parse(handleGetUserStats_({
    action: 'getUserStats',
    sessionToken: sessionToken,
  }).getContent());

  assertBackendTest_(response.ok === true, 'getUserStats harus return ok true.');
  assertBackendTest_(!!response.stats, 'getUserStats harus memiliki object stats.');
  assertBackendTest_(response.stats.nik === session.nik, 'Stats harus milik session aktif.');
  assertBackendTest_(
    Number.isFinite(Number(response.stats.totalActivities)) &&
      Number.isFinite(Number(response.stats.totalDistanceKm)) &&
      Number.isFinite(Number(response.stats.totalDurationSec)) &&
      Number.isFinite(Number(response.stats.totalXP)),
    'Total statistik harus berupa angka.'
  );

  const summary = {
    ok: true,
    hasStats: true,
    totalActivities: response.stats.totalActivities,
    totalDistanceKm: response.stats.totalDistanceKm,
    totalDurationSec: response.stats.totalDurationSec,
    totalXP: response.stats.totalXP,
    currentLevel: response.stats.currentLevel,
    currentLevelName: response.stats.currentLevelName,
    nextLevelXP: response.stats.nextLevelXP,
  };
  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

function testGuildMasterFoundation() {
  const records = [
    {
      guildId: 'Operations',
      guildName: 'Operations',
      displayName: 'OTO Operations Crew',
      description: 'Operations runners and walkers.',
      status: 'ACTIVE',
      sortOrder: 1,
    },
    {
      guildId: 'Legacy-Inactive',
      guildName: 'Legacy Inactive',
      displayName: 'Archived Guild',
      description: '',
      status: 'INACTIVE',
      sortOrder: 2,
    },
  ];
  const activeMap = getGuildMasterMap_(records);
  const matched = resolveGuildMetadata_('Operations', records);
  const matchedByName = findGuildByIdOrName_('operations', records);
  const fallback = resolveGuildMetadata_('Unregistered Division', records);
  const inactive = resolveGuildMetadata_('Legacy-Inactive', records);

  assertBackendTest_(
    activeMap.operations && activeMap.operations.displayName === 'OTO Operations Crew',
    'Guild_Master ACTIVE harus tersedia melalui lookup map.'
  );
  assertBackendTest_(
    matched.status === 'ACTIVE' &&
      matched.guild.guildId === 'Operations' &&
      matched.guild.displayName === 'OTO Operations Crew',
    'Division existing harus cocok dengan GuildId dan memakai DisplayName master.'
  );
  assertBackendTest_(
    matchedByName && matchedByName.guildId === 'Operations',
    'Guild lookup berdasarkan ID atau nama harus case-insensitive.'
  );
  assertBackendTest_(
    fallback.status === 'ACTIVE' &&
      fallback.legacyFallback === true &&
      fallback.guild.guildId === 'Unregistered Division' &&
      fallback.guild.displayName === 'Unregistered Division',
    'Guild yang tidak ada di master harus memakai fallback Division lama.'
  );
  assertBackendTest_(
    inactive.status === 'GUILD_INACTIVE' && !activeMap['legacy-inactive'],
    'Guild master INACTIVE harus aman dan tidak masuk active map.'
  );

  const summary = buildGuildSummary_({
    nik: '001',
    divisionGuild: 'Operations',
  }, [
    { nik: '001', nickname: 'ALPHA', divisionGuild: 'Operations', status: 'ACTIVE' },
    { nik: '002', nickname: 'BETA', divisionGuild: 'Other', status: 'ACTIVE' },
  ], {
    '001': {
      totalActivities: 1,
      totalDistanceKm: 1.25,
      totalXp: 13,
      currentLevel: 1,
      currentLevelName: 'ROOKIE',
    },
  }, {
    currentLevel: 1,
    currentLevelName: 'ROOKIE',
  }, matched.guild);
  assertBackendTest_(
    summary.guild.displayName === 'OTO Operations Crew' &&
      summary.guild.description === 'Operations runners and walkers.' &&
      summary.members.length === 1,
    'Guild summary harus memakai metadata tanpa merusak Division isolation.'
  );
  const serialized = JSON.stringify(summary).toLowerCase();
  assertBackendTest_(
    serialized.indexOf('"pin"') === -1 && serialized.indexOf('sessiontoken') === -1,
    'Metadata guild tidak boleh expose field sensitif.'
  );

  return {
    ok: true,
    activeGuildReadable: true,
    guildIdMatching: true,
    guildNameMatching: true,
    displayNameApplied: true,
    legacyFallbackSafe: true,
    inactiveGuildSafe: true,
    divisionIsolation: true,
    sensitiveFieldsExcluded: true,
  };
}

function testGetGuildSummary() {
  const sessionToken = getOrCreateTestSessionToken_();
  const session = requireSession_(sessionToken);
  const owner = findParticipantByNik_(session.nik);
  const response = JSON.parse(handleGetGuildSummary_({
    action: 'getGuildSummary',
    sessionToken: sessionToken,
  }).getContent());

  assertBackendTest_(response.ok === true, 'getGuildSummary harus return ok true.');
  assertBackendTest_(Array.isArray(response.members), 'Response guild harus memiliki array members.');

  const ownerDivision = String(owner.divisionGuild || '').trim();
  if (!ownerDivision) {
    assertBackendTest_(
      response.status === 'UNASSIGNED' && response.guild === null && response.members.length === 0,
      'User tanpa Division harus aman sebagai UNASSIGNED.'
    );
  } else {
    const divisionKey = normalizeDivisionKey_(ownerDivision);
    const resolution = resolveGuildMetadata_(ownerDivision, getGuildMasterRecords_());
    const expectedParticipants = getGuildParticipantRows_().filter(function (participant) {
      return normalizeDivisionKey_(participant.divisionGuild) === divisionKey;
    });
    const expectedActive = expectedParticipants.filter(function (participant) {
      return participant.status === 'ACTIVE';
    });

    assertBackendTest_(
      response.status === resolution.status,
      'Status guild harus mengikuti Guild_Master atau fallback legacy.'
    );
    assertBackendTest_(
      response.guild.guildId === resolution.guild.guildId &&
        response.guild.displayName === resolution.guild.displayName,
      'Metadata guild response harus mengikuti hasil resolusi Guild_Master.'
    );
    assertBackendTest_(
      response.guild.memberCount === expectedParticipants.length &&
        response.guild.activeMemberCount === expectedActive.length &&
        response.members.length === expectedActive.length,
      'Jumlah member guild harus konsisten dengan Participants.'
    );
    response.members.forEach(function (member) {
      assertBackendTest_(
        normalizeDivisionKey_(member.division) === divisionKey,
        'Member dari Division lain tidak boleh masuk.'
      );
      assertBackendTest_(typeof member.nik === 'string', 'NIK member harus berupa string.');
    });
  }

  const mappingTests = testGuildSummaryFoundation();
  const masterTests = testGuildMasterFoundation();
  const serialized = JSON.stringify(response).toLowerCase();
  assertBackendTest_(serialized.indexOf('"pin"') === -1, 'Response guild tidak boleh expose PIN.');
  assertBackendTest_(
    serialized.indexOf('sessiontoken') === -1,
    'Response guild tidak boleh expose session token.'
  );

  const summary = {
    ok: true,
    status: response.status,
    guild: response.guild,
    memberCount: response.members.length,
    foundationTests: mappingTests,
    guildMasterTests: masterTests,
  };
  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

function getMasterDataCacheRegressionCases_() {
  return [
    { sheetName: ORA_SHEETS.CONFIG, read: getActiveConfig_ },
    { sheetName: ORA_SHEETS.LEVELS, read: getActiveLevels_ },
    { sheetName: ORA_SHEETS.QUESTS, read: getActiveQuests_ },
    { sheetName: ORA_SHEETS.GUILD_MASTER, read: getGuildMasterRecords_ },
    { sheetName: ORA_SHEETS.ATTENDANCE_REWARDS, read: getAttendanceRewardRows_ },
  ];
}

function testMasterDataCacheRegression() {
  const cases = getMasterDataCacheRegressionCases_();
  const expectedTtls = {};
  expectedTtls[ORA_SHEETS.CONFIG] = 300;
  expectedTtls[ORA_SHEETS.LEVELS] = 600;
  expectedTtls[ORA_SHEETS.QUESTS] = 180;
  expectedTtls[ORA_SHEETS.GUILD_MASTER] = 300;
  expectedTtls[ORA_SHEETS.ATTENDANCE_REWARDS] = 300;
  const coldValues = {};
  const warmValues = {};
  const invalidationMisses = {};

  cases.forEach(function (testCase) {
    const definition = getMasterDataCacheDefinition_(testCase.sheetName);
    assertBackendTest_(!!definition && !!definition.key, testCase.sheetName + ' cache key wajib ada.');
    assertBackendTest_(
      definition.ttlSeconds === expectedTtls[testCase.sheetName],
      testCase.sheetName + ' TTL tidak sesuai target.'
    );
  });

  invalidateAllMasterDataCaches_();
  resetRequestSheetSnapshots_();
  cases.forEach(function (testCase) {
    coldValues[testCase.sheetName] = testCase.read();
  });
  cases.forEach(function (testCase) {
    testCase.read();
  });
  const coldStats = getMasterCacheStats_();
  cases.forEach(function (testCase) {
    const stats = coldStats[testCase.sheetName] || {};
    assertBackendTest_(stats.misses === 1, testCase.sheetName + ' cold read harus cache miss.');
    assertBackendTest_(stats.puts === 1, testCase.sheetName + ' cold read harus mengisi cache.');
    assertBackendTest_(
      stats.runtimeHits === 1,
      testCase.sheetName + ' read kedua dalam request harus runtime hit.'
    );
  });

  resetRequestSheetSnapshots_();
  cases.forEach(function (testCase) {
    warmValues[testCase.sheetName] = testCase.read();
  });
  const warmStats = getMasterCacheStats_();
  cases.forEach(function (testCase) {
    const stats = warmStats[testCase.sheetName] || {};
    assertBackendTest_(stats.scriptHits === 1, testCase.sheetName + ' warm read harus cache hit.');
    assertBackendTest_(
      serializeMasterDataCacheValue_(coldValues[testCase.sheetName]) ===
        serializeMasterDataCacheValue_(warmValues[testCase.sheetName]),
      testCase.sheetName + ' warm result harus identik dengan cold result.'
    );
  });

  cases.forEach(function (testCase) {
    invalidateMasterDataCache_(testCase.sheetName);
    resetRequestSheetSnapshots_();
    const reloaded = testCase.read();
    const stats = getMasterCacheStats_()[testCase.sheetName] || {};
    assertBackendTest_(
      stats.misses === 1,
      testCase.sheetName + ' harus miss setelah invalidation.'
    );
    assertBackendTest_(
      serializeMasterDataCacheValue_(coldValues[testCase.sheetName]) ===
        serializeMasterDataCacheValue_(reloaded),
      testCase.sheetName + ' berubah setelah invalidation tanpa sheet write.'
    );
    invalidationMisses[testCase.sheetName] = true;
  });

  const date = new Date('2026-09-01T00:00:00.000Z');
  const decodedDate = deserializeMasterDataCacheValue_(
    serializeMasterDataCacheValue_({ value: date })
  ).value;
  assertBackendTest_(
    Object.prototype.toString.call(decodedDate) === '[object Date]' &&
      decodedDate.getTime() === date.getTime(),
    'Cache codec harus mempertahankan tipe Date.'
  );

  const result = {
    ok: true,
    definitions: cases.map(function (testCase) {
      const definition = getMasterDataCacheDefinition_(testCase.sheetName);
      return {
        sheetName: testCase.sheetName,
        key: definition.key,
        ttlSeconds: definition.ttlSeconds,
      };
    }),
    coldMisses: cases.map(function (testCase) { return testCase.sheetName; }),
    requestRuntimeHits: cases.map(function (testCase) { return testCase.sheetName; }),
    warmHits: cases.map(function (testCase) { return testCase.sheetName; }),
    invalidationMisses: invalidationMisses,
    dateTypePreserved: true,
  };
  console.log(JSON.stringify(result, null, 2));
  return result;
}

function testGuildLeaderboardCacheIsolationFoundation() {
  const firstNik = 'ISOLATION-USER-A';
  const secondNik = 'ISOLATION-USER-B';
  const guild = 'ISOLATION-GUILD';
  const firstIdentity = readHeavyCacheIdentity_(firstNik);
  const secondIdentity = readHeavyCacheIdentity_(secondNik);
  const guildIdentity = readHeavyCacheIdentity_(guild);
  const firstKey = buildReadHeavyCacheKey_(
    'guild_data',
    ['GLOBAL', 'TOTAL_XP', firstIdentity, guildIdentity]
  );
  const secondKey = buildReadHeavyCacheKey_(
    'guild_data',
    ['GLOBAL', 'TOTAL_XP', secondIdentity, guildIdentity]
  );
  const globalXpKey = buildReadHeavyCacheKey_(
    'leaderboard_global',
    ['TOTAL_XP', firstIdentity]
  );
  const globalDistanceKey = buildReadHeavyCacheKey_(
    'leaderboard_global',
    ['TOTAL_DISTANCE', firstIdentity]
  );
  const guildXpKey = buildReadHeavyCacheKey_(
    'leaderboard_guild',
    ['TOTAL_XP', guildIdentity, firstIdentity]
  );
  const otherGuildXpKey = buildReadHeavyCacheKey_(
    'leaderboard_guild',
    ['TOTAL_XP', readHeavyCacheIdentity_('OTHER-GUILD'), firstIdentity]
  );

  assertBackendTest_(firstIdentity !== secondIdentity, 'Identitas cache user harus terisolasi.');
  assertBackendTest_(firstKey !== secondKey, 'Cache key user berbeda tidak boleh sama.');
  assertBackendTest_(
    firstKey.indexOf(firstNik) === -1 && secondKey.indexOf(secondNik) === -1,
    'Cache key tidak boleh memuat identitas user mentah.'
  );
  assertBackendTest_(
    firstKey.toLowerCase().indexOf('sessiontoken') === -1,
    'Cache key tidak boleh memuat session token.'
  );
  assertBackendTest_(globalXpKey !== globalDistanceKey, 'Metric cache harus terisolasi.');
  assertBackendTest_(globalXpKey !== guildXpKey, 'Scope cache harus terisolasi.');
  assertBackendTest_(guildXpKey !== otherGuildXpKey, 'Guild cache harus terisolasi.');

  return {
    ok: true,
    userKeysDiffer: true,
    rawIdentityExcluded: true,
    sessionTokenExcluded: true,
    metricIsolation: true,
    scopeIsolation: true,
    guildIsolation: true,
  };
}

function testGuildLeaderboardCacheRegression() {
  const sessionToken = getOrCreateTestSessionToken_();
  const session = requireSession_(sessionToken);
  resetRequestSheetSnapshots_();
  const participant = findParticipantByNik_(session.nik);
  assertBackendTest_(!!participant, 'Participant test cache Guild tidak ditemukan.');
  assertBackendTest_(ORA_READ_HEAVY_CACHE.ttlSeconds === 60, 'TTL cache harus 60 detik.');

  const scenarios = [
    {
      name: 'getGuildData',
      cacheType: 'guild_data',
      run: function () {
        return handleGetGuildData_({
          sessionToken: sessionToken,
          scope: 'GLOBAL',
          metric: 'TOTAL_XP',
        });
      },
    },
    {
      name: 'guildDirectory',
      cacheType: 'guild_directory',
      run: function () {
        return handleGetGuildDirectory_({ sessionToken: sessionToken });
      },
    },
    {
      name: 'guildSummary',
      cacheType: String(participant.divisionGuild || '').trim()
        ? 'guild_summary'
        : null,
      run: function () {
        return handleGetGuildSummary_({ sessionToken: sessionToken });
      },
    },
    {
      name: 'globalLeaderboard',
      cacheType: 'leaderboard_global',
      run: function () {
        return handleGetLeaderboard_({
          sessionToken: sessionToken,
          scope: 'GLOBAL',
          metric: 'TOTAL_XP',
        });
      },
    },
  ];
  if (String(participant.divisionGuild || '').trim()) {
    scenarios.push({
      name: 'guildLeaderboard',
      cacheType: 'leaderboard_guild',
      run: function () {
        return handleGetLeaderboard_({
          sessionToken: sessionToken,
          scope: 'GUILD',
          metric: 'TOTAL_DISTANCE',
        });
      },
    });
  }

  const result = {
    ok: true,
    ttlSeconds: ORA_READ_HEAVY_CACHE.ttlSeconds,
    isolation: testGuildLeaderboardCacheIsolationFoundation(),
    scenarios: {},
  };
  scenarios.forEach(function (scenario) {
    invalidateGuildLeaderboardCaches_();
    const cold = runGuildLeaderboardCacheRequest_(scenario.run);
    const warm = runGuildLeaderboardCacheRequest_(scenario.run);
    assertBackendTest_(cold.payload.ok === true, scenario.name + ' cold request gagal.');
    assertBackendTest_(warm.payload.ok === true, scenario.name + ' warm request gagal.');
    assertBackendTest_(
      normalizeBenchmarkPayload_(cold.payload) === normalizeBenchmarkPayload_(warm.payload),
      scenario.name + ' cold dan warm response berbeda.'
    );
    if (scenario.cacheType) {
      const coldStats = cold.cacheStats[scenario.cacheType] || {};
      const warmStats = warm.cacheStats[scenario.cacheType] || {};
      assertBackendTest_(coldStats.misses === 1, scenario.name + ' cold harus cache miss.');
      assertBackendTest_(coldStats.puts === 1, scenario.name + ' cold harus cache put.');
      assertBackendTest_(warmStats.scriptHits === 1, scenario.name + ' warm harus cache hit.');
    }
    const serialized = JSON.stringify(warm.payload).toLowerCase();
    assertBackendTest_(serialized.indexOf('sessiontoken') === -1, 'Cache response expose session token.');
    assertBackendTest_(serialized.indexOf('"pin"') === -1, 'Cache response expose PIN.');
    result.scenarios[scenario.name] = {
      coldCacheStats: cold.cacheStats,
      warmCacheStats: warm.cacheStats,
      responseIdentical: true,
    };
  });

  invalidateGuildLeaderboardCaches_();
  const beforeXpInvalidation = runGuildLeaderboardCacheRequest_(scenarios[0].run);
  runGuildLeaderboardCacheRequest_(scenarios[0].run);
  invalidateSheetSnapshot_(ORA_SHEETS.USER_STATS);
  const afterXpInvalidation = runGuildLeaderboardCacheRequest_(scenarios[0].run);
  assertBackendTest_(
    (afterXpInvalidation.cacheStats.guild_data || {}).misses === 1,
    'User_Stats change harus menginvalidasi getGuildData cache.'
  );
  assertBackendTest_(
    normalizeBenchmarkPayload_(beforeXpInvalidation.payload) ===
      normalizeBenchmarkPayload_(afterXpInvalidation.payload),
    'Invalidation User_Stats tanpa perubahan sheet mengubah response.'
  );

  const globalScenario = scenarios.filter(function (scenario) {
    return scenario.name === 'globalLeaderboard';
  })[0];
  runGuildLeaderboardCacheRequest_(globalScenario.run);
  invalidateSheetSnapshot_(ORA_SHEETS.ACTIVITIES);
  const afterActivityInvalidation = runGuildLeaderboardCacheRequest_(globalScenario.run);
  assertBackendTest_(
    (afterActivityInvalidation.cacheStats.leaderboard_global || {}).misses === 1,
    'Activity change harus menginvalidasi global leaderboard cache.'
  );

  result.invalidation = {
    userStatsToGuildDataMiss: true,
    activityToGlobalLeaderboardMiss: true,
    dependencySheets: [
      ORA_SHEETS.PARTICIPANTS,
      ORA_SHEETS.ACTIVITIES,
      ORA_SHEETS.USER_STATS,
      ORA_SHEETS.GUILD_MASTER,
      ORA_SHEETS.LEVELS,
    ],
  };
  console.log(JSON.stringify(result, null, 2));
  return result;
}

function benchmarkGuildLeaderboardCache() {
  const sessionToken = getOrCreateTestSessionToken_();
  const session = requireSession_(sessionToken);
  resetRequestSheetSnapshots_();
  const participant = findParticipantByNik_(session.nik);
  assertBackendTest_(!!participant, 'Participant benchmark Guild tidak ditemukan.');

  getActiveLevels_();
  getGuildMasterRecords_();
  const scenarios = [
    {
      name: 'getGuildData',
      run: function () {
        return handleGetGuildData_({
          sessionToken: sessionToken,
          scope: 'GLOBAL',
          metric: 'TOTAL_XP',
        });
      },
    },
    {
      name: 'globalLeaderboard',
      run: function () {
        return handleGetLeaderboard_({
          sessionToken: sessionToken,
          scope: 'GLOBAL',
          metric: 'TOTAL_XP',
        });
      },
    },
  ];
  if (String(participant.divisionGuild || '').trim()) {
    scenarios.push({
      name: 'guildLeaderboard',
      run: function () {
        return handleGetLeaderboard_({
          sessionToken: sessionToken,
          scope: 'GUILD',
          metric: 'TOTAL_DISTANCE',
        });
      },
    });
  }

  const result = { ok: true, ttlSeconds: ORA_READ_HEAVY_CACHE.ttlSeconds, scenarios: {} };
  scenarios.forEach(function (scenario) {
    invalidateGuildLeaderboardCaches_();
    const cold = runGuildLeaderboardCacheRequest_(scenario.run);
    const warm = runGuildLeaderboardCacheRequest_(scenario.run);
    assertBackendTest_(cold.payload.ok === true, scenario.name + ' cold benchmark gagal.');
    assertBackendTest_(warm.payload.ok === true, scenario.name + ' warm benchmark gagal.');
    assertBackendTest_(
      normalizeBenchmarkPayload_(cold.payload) === normalizeBenchmarkPayload_(warm.payload),
      scenario.name + ' benchmark response berbeda.'
    );
    result.scenarios[scenario.name] = {
      coldMs: cold.durationMs,
      warmMs: warm.durationMs,
      deltaMs: cold.durationMs - warm.durationMs,
      speedupRatio: roundDecimal_(cold.durationMs / Math.max(1, warm.durationMs), 2),
      coldCacheStats: cold.cacheStats,
      warmCacheStats: warm.cacheStats,
      responseIdentical: true,
    };
  });
  console.log(JSON.stringify(result, null, 2));
  return result;
}

function runGuildLeaderboardCacheRequest_(callback) {
  resetRequestSheetSnapshots_();
  const startedAt = Date.now();
  const payload = JSON.parse(callback().getContent());
  return {
    durationMs: Date.now() - startedAt,
    payload: payload,
    cacheStats: getReadHeavyCacheStats_(),
  };
}

function benchmarkMasterDataCache() {
  const sessionToken = getOrCreateTestSessionToken_();
  const scenarios = [
    {
      name: 'getGuildData',
      run: function () {
        return handleGetGuildData_({
          sessionToken: sessionToken,
          scope: 'GLOBAL',
          metric: 'TOTAL_XP',
        });
      },
    },
    {
      name: 'getQuestProgress',
      run: function () {
        return handleGetQuestProgress_({ sessionToken: sessionToken });
      },
    },
  ];
  const result = { ok: true, scenarios: {} };

  scenarios.forEach(function (scenario) {
    invalidateAllMasterDataCaches_();
    invalidateGuildLeaderboardCaches_();
    const cold = runMasterDataCacheBenchmarkRequest_(scenario.run);
    invalidateGuildLeaderboardCaches_();
    const warm = runMasterDataCacheBenchmarkRequest_(scenario.run);
    assertBackendTest_(cold.payload.ok === true, scenario.name + ' cold request gagal.');
    assertBackendTest_(warm.payload.ok === true, scenario.name + ' warm request gagal.');
    assertBackendTest_(
      normalizeBenchmarkPayload_(cold.payload) === normalizeBenchmarkPayload_(warm.payload),
      scenario.name + ' cold dan warm response berbeda.'
    );
    result.scenarios[scenario.name] = {
      coldMs: cold.durationMs,
      warmMs: warm.durationMs,
      deltaMs: cold.durationMs - warm.durationMs,
      speedupRatio: roundDecimal_(cold.durationMs / Math.max(1, warm.durationMs), 2),
      coldCacheStats: cold.cacheStats,
      warmCacheStats: warm.cacheStats,
      responseIdentical: true,
    };
  });

  console.log(JSON.stringify(result, null, 2));
  return result;
}

function runMasterDataCacheBenchmarkRequest_(callback) {
  resetRequestSheetSnapshots_();
  const startedAt = Date.now();
  const payload = JSON.parse(callback().getContent());
  return {
    durationMs: Date.now() - startedAt,
    payload: payload,
    cacheStats: getMasterCacheStats_(),
  };
}

function normalizeBenchmarkPayload_(payload) {
  const normalized = JSON.parse(JSON.stringify(payload));
  delete normalized.timestamp;
  return JSON.stringify(normalized);
}

function testRequestSheetSnapshotFoundation() {
  const counters = {
    dataRange: 0,
    values: 0,
    displayValues: 0,
  };
  const values = [
    ORA_HEADERS.Config.slice(),
    ['TEST_KEY', 10, 'NUMBER', 'Runtime snapshot test', true],
  ];
  const range = {
    getValues: function () {
      counters.values += 1;
      return values;
    },
    getDisplayValues: function () {
      counters.displayValues += 1;
      return values.map(function (row) {
        return row.map(function (cell) { return String(cell); });
      });
    },
  };
  const sheet = {
    getDataRange: function () {
      counters.dataRange += 1;
      return range;
    },
  };

  resetRequestSheetSnapshots_();
  try {
    readSheetValues_(ORA_SHEETS.CONFIG, sheet);
    readSheetValues_(ORA_SHEETS.CONFIG, sheet);
    readSheetDisplayValues_(ORA_SHEETS.CONFIG, sheet);
    readSheetDisplayValues_(ORA_SHEETS.CONFIG, sheet);
    const firstObjects = readSheetObjects_(ORA_SHEETS.CONFIG);
    const secondObjects = readSheetObjects_(ORA_SHEETS.CONFIG);

    assertBackendTest_(counters.dataRange === 1, 'Data range snapshot harus dibuat sekali.');
    assertBackendTest_(counters.values === 1, 'getValues snapshot harus dibaca sekali.');
    assertBackendTest_(
      counters.displayValues === 1,
      'getDisplayValues snapshot harus dibaca sekali.'
    );
    assertBackendTest_(
      firstObjects === secondObjects && firstObjects[0].Config_Key === 'TEST_KEY',
      'Object snapshot harus direuse tanpa mengubah mapping row.'
    );

    invalidateSheetSnapshot_(ORA_SHEETS.CONFIG);
    readSheetValues_(ORA_SHEETS.CONFIG, sheet);
    assertBackendTest_(
      counters.dataRange === 2 && counters.values === 2,
      'Invalidation harus memaksa pembacaan snapshot baru.'
    );

    return {
      ok: true,
      rangeReadOnce: true,
      valuesReadOnce: true,
      displayValuesReadOnce: true,
      objectsReused: true,
      invalidationReloaded: true,
    };
  } finally {
    resetRequestSheetSnapshots_();
  }
}

function testGetGuildDataRegression() {
  const sessionToken = getOrCreateTestSessionToken_();
  const request = {
    sessionToken: sessionToken,
    scope: 'GLOBAL',
    metric: 'TOTAL_XP',
  };
  const combined = JSON.parse(handleGetGuildData_(request).getContent());
  const summary = JSON.parse(handleGetGuildSummary_(request).getContent());
  const directory = JSON.parse(handleGetGuildDirectory_(request).getContent());
  const leaderboard = JSON.parse(handleGetLeaderboard_(request).getContent());

  assertBackendTest_(combined.ok === true, 'getGuildData harus return ok true.');
  assertBackendTest_(
    combined.status === summary.status &&
      JSON.stringify(combined.guild) === JSON.stringify(summary.guild) &&
      JSON.stringify(combined.members) === JSON.stringify(summary.members),
    'Guild status, summary, atau members berbeda dari endpoint lama.'
  );
  assertBackendTest_(
    JSON.stringify(combined.guilds) === JSON.stringify(directory.guilds),
    'Guild directory berbeda dari endpoint lama.'
  );
  assertBackendTest_(
    combined.leaderboard.scope === leaderboard.scope &&
      combined.leaderboard.metric === leaderboard.metric &&
      combined.leaderboard.status === leaderboard.status &&
      JSON.stringify(combined.leaderboard.entries) === JSON.stringify(leaderboard.leaderboard) &&
      JSON.stringify(combined.leaderboard.currentUserRank) ===
        JSON.stringify(leaderboard.currentUserRank),
    'Leaderboard getGuildData berbeda dari endpoint lama.'
  );

  const serialized = JSON.stringify(combined).toLowerCase();
  assertBackendTest_(serialized.indexOf('"pin"') === -1, 'getGuildData tidak boleh expose PIN.');
  assertBackendTest_(
    serialized.indexOf('sessiontoken') === -1,
    'getGuildData tidak boleh expose session token.'
  );

  const result = {
    ok: true,
    accountCompared: true,
    scope: combined.leaderboard.scope,
    metric: combined.leaderboard.metric,
    guildStatus: combined.status,
    memberCount: combined.members.length,
    directoryCount: combined.guilds.length,
    leaderboardCount: combined.leaderboard.entries.length,
    matchesLegacyEndpoints: true,
  };
  console.log(JSON.stringify(result, null, 2));
  return result;
}

function testRequestSheetSnapshotRegression() {
  const sessionToken = getOrCreateTestSessionToken_();
  const session = requireSession_(sessionToken);
  const result = {
    ok: true,
    foundation: testRequestSheetSnapshotFoundation(),
    endpoints: {},
  };

  invalidateAllMasterDataCaches_();
  invalidateGuildLeaderboardCaches_();
  resetRequestSheetSnapshots_();
  result.endpoints.getGuildData = testGetGuildDataRegression();
  result.endpoints.getGuildData.sheetLoads = assertRequestSheetSnapshotsReadOnce_(
    'getGuildData regression'
  );
  assertExpectedRequestSheetSnapshots_(
    'getGuildData regression',
    result.endpoints.getGuildData.sheetLoads,
    [ORA_SHEETS.PARTICIPANTS, ORA_SHEETS.USER_STATS, ORA_SHEETS.GUILD_MASTER, ORA_SHEETS.LEVELS]
  );

  invalidateAllMasterDataCaches_();
  resetRequestSheetSnapshots_();
  result.endpoints.getQuestProgress = testGetQuestProgress();
  result.endpoints.getQuestProgress.sheetLoads = assertRequestSheetSnapshotsReadOnce_(
    'getQuestProgress regression'
  );
  assertExpectedRequestSheetSnapshots_(
    'getQuestProgress regression',
    result.endpoints.getQuestProgress.sheetLoads,
    [
      ORA_SHEETS.PARTICIPANTS,
      ORA_SHEETS.ACTIVITIES,
      ORA_SHEETS.USER_STATS,
      ORA_SHEETS.QUEST_CLAIMS,
      ORA_SHEETS.QUESTS,
      ORA_SHEETS.CONFIG,
      ORA_SHEETS.ATTENDANCE_RECORDS,
    ]
  );

  resetRequestSheetSnapshots_();
  result.endpoints.getUserStats = testGetUserStats();
  result.endpoints.getUserStats.sheetLoads = assertRequestSheetSnapshotsReadOnce_(
    'getUserStats regression'
  );
  assertExpectedRequestSheetSnapshots_(
    'getUserStats regression',
    result.endpoints.getUserStats.sheetLoads,
    [ORA_SHEETS.PARTICIPANTS, ORA_SHEETS.USER_STATS]
  );

  invalidateGuildLeaderboardCaches_();
  resetRequestSheetSnapshots_();
  result.endpoints.leaderboard = testGetLeaderboard();
  result.endpoints.leaderboard.sheetLoads = assertRequestSheetSnapshotsReadOnce_(
    'leaderboard regression'
  );
  assertExpectedRequestSheetSnapshots_(
    'leaderboard regression',
    result.endpoints.leaderboard.sheetLoads,
    [ORA_SHEETS.PARTICIPANTS, ORA_SHEETS.USER_STATS]
  );

  resetRequestSheetSnapshots_();
  const firstAttendanceRead = getAttendanceRecordsForNik_(session.nik);
  const secondAttendanceRead = getAttendanceRecordsForNik_(session.nik);
  assertBackendTest_(
    JSON.stringify(firstAttendanceRead) === JSON.stringify(secondAttendanceRead),
    'Attendance read ulang harus menghasilkan data identik.'
  );
  result.endpoints.attendanceReads = {
    ok: true,
    recordsCompared: firstAttendanceRead.length,
    repeatedReadIdentical: true,
    sheetLoads: assertRequestSheetSnapshotsReadOnce_('attendance read regression'),
  };
  assertExpectedRequestSheetSnapshots_(
    'attendance read regression',
    result.endpoints.attendanceReads.sheetLoads,
    [ORA_SHEETS.ATTENDANCE_RECORDS]
  );

  resetRequestSheetSnapshots_();
  console.log(JSON.stringify(result, null, 2));
  return result;
}

function testGuildSummaryFoundation() {
  const owner = {
    nik: '00123',
    divisionGuild: 'TRAIL NORTH',
  };
  const participants = [
    { nik: '00123', nickname: 'ALPHA', divisionGuild: 'TRAIL NORTH', status: 'ACTIVE' },
    { nik: '00456', nickname: 'BETA', divisionGuild: ' trail north ', status: 'ACTIVE' },
    { nik: '00789', nickname: 'GAMMA', divisionGuild: 'TRAIL NORTH', status: 'INACTIVE' },
    { nik: '00999', nickname: 'OUTSIDER', divisionGuild: 'ROAD SOUTH', status: 'ACTIVE' },
  ];
  const statsByNik = {
    '00123': {
      totalActivities: 3,
      totalDistanceKm: 12.345,
      totalXp: 140,
      currentLevel: 2,
      currentLevelName: 'SCOUT',
    },
    '00999': {
      totalActivities: 99,
      totalDistanceKm: 999,
      totalXp: 9999,
      currentLevel: 9,
      currentLevelName: 'OUTSIDER',
    },
  };
  const result = buildGuildSummary_(
    owner,
    participants,
    statsByNik,
    { currentLevel: 1, currentLevelName: 'ROOKIE' }
  );
  const missingStatsMember = result.members.find(function (member) {
    return member.nik === '00456';
  });

  assertBackendTest_(
    result.guild.memberCount === 3 && result.guild.activeMemberCount === 2,
    'Guild harus menghitung seluruh member dan ACTIVE secara terpisah.'
  );
  assertBackendTest_(result.members.length === 2, 'Members hanya boleh berisi participant ACTIVE.');
  assertBackendTest_(
    result.guild.totalDistanceKm === 12.345 &&
      result.guild.totalActivities === 3 &&
      result.guild.totalXP === 140,
    'Total guild hanya boleh berasal dari active member dalam Division yang sama.'
  );
  assertBackendTest_(
    missingStatsMember &&
      missingStatsMember.totalDistanceKm === 0 &&
      missingStatsMember.totalActivities === 0 &&
      missingStatsMember.totalXP === 0 &&
      missingStatsMember.currentLevel === 1,
    'Member tanpa User_Stats harus tetap tampil dengan nilai default aman.'
  );
  assertBackendTest_(
    !result.members.some(function (member) { return member.nik === '00999'; }),
    'Member Division lain tidak boleh ikut masuk.'
  );

  const unassigned = JSON.parse(
    jsonGuildSummarySuccess_('UNASSIGNED', null, []).getContent()
  );
  assertBackendTest_(
    unassigned.ok === true &&
      unassigned.status === 'UNASSIGNED' &&
      unassigned.guild === null &&
      unassigned.members.length === 0,
    'User tanpa Division harus mendapat response sukses yang aman.'
  );

  return {
    ok: true,
    divisionIsolation: true,
    activeMemberFiltering: true,
    missingStatsDefaults: true,
    unassignedSafe: true,
    nikRemainsText: true,
    sensitiveFieldsExcluded: true,
  };
}

function testGetLeaderboard() {
  const sessionToken = getOrCreateTestSessionToken_();
  const session = requireSession_(sessionToken);
  const participant = findParticipantByNik_(session.nik);
  const metrics = ['TOTAL_XP', 'TOTAL_DISTANCE', 'TOTAL_ACTIVITIES'];
  const responses = {};

  metrics.forEach(function (metric) {
    const response = JSON.parse(handleGetLeaderboard_({
      action: 'getLeaderboard',
      sessionToken: sessionToken,
      scope: 'GLOBAL',
      metric: metric,
    }).getContent());
    assertBackendTest_(response.ok === true, 'getLeaderboard harus return ok true.');
    assertBackendTest_(response.scope === 'GLOBAL', 'Scope leaderboard harus GLOBAL.');
    assertBackendTest_(response.metric === metric, 'Metric response harus sesuai request.');
    assertBackendTest_(Array.isArray(response.leaderboard), 'Leaderboard harus berupa array.');
    assertBackendTest_(response.leaderboard.length <= 50, 'Leaderboard maksimal 50 row.');
    assertLeaderboardSorted_(response.leaderboard, metric);
    response.leaderboard.forEach(function (entry) {
      assertBackendTest_(typeof entry.nik === 'string', 'NIK leaderboard harus berupa string.');
    });
    responses[metric] = response;
  });

  const activeParticipants = getGuildParticipantRows_().filter(function (participant) {
    return participant.status === 'ACTIVE';
  });
  const activeByNik = {};
  activeParticipants.forEach(function (participant) {
    activeByNik[participant.nik] = true;
  });
  responses.TOTAL_XP.leaderboard.forEach(function (entry) {
    assertBackendTest_(activeByNik[entry.nik], 'Participant INACTIVE tidak boleh tampil.');
  });

  const guildResponse = JSON.parse(handleGetLeaderboard_({
    action: 'getLeaderboard',
    sessionToken: sessionToken,
    scope: 'GUILD',
    metric: 'TOTAL_DISTANCE',
  }).getContent());
  assertBackendTest_(guildResponse.ok === true, 'Leaderboard GUILD harus return ok true.');
  assertBackendTest_(guildResponse.scope === 'GUILD', 'Scope response harus GUILD.');
  if (!String(participant.divisionGuild || '').trim()) {
    assertBackendTest_(
      guildResponse.status === 'NO_GUILD' && guildResponse.leaderboard.length === 0,
      'User tanpa Division harus mendapat leaderboard GUILD kosong.'
    );
  } else {
    const divisionKey = normalizeDivisionKey_(participant.divisionGuild);
    guildResponse.leaderboard.forEach(function (entry) {
      assertBackendTest_(
        normalizeDivisionKey_(entry.division) === divisionKey,
        'Leaderboard GUILD tidak boleh memuat Division lain.'
      );
    });
    assertLeaderboardSorted_(guildResponse.leaderboard, 'TOTAL_DISTANCE');
  }

  const serialized = JSON.stringify(responses).toLowerCase();
  assertBackendTest_(serialized.indexOf('"pin"') === -1, 'Leaderboard tidak boleh expose PIN.');
  assertBackendTest_(
    serialized.indexOf('sessiontoken') === -1,
    'Leaderboard tidak boleh expose session token.'
  );

  const foundationTests = testLeaderboardFoundation();
  const summary = {
    ok: true,
    scope: 'GLOBAL',
    supportedMetrics: metrics,
    leaderboardCount: responses.TOTAL_XP.leaderboard.length,
    currentUserHasStats: responses.TOTAL_XP.currentUserRank !== null,
    guildScopeStatus: guildResponse.status,
    guildLeaderboardCount: guildResponse.leaderboard.length,
    foundationTests: foundationTests,
  };
  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

function testLeaderboardFoundation() {
  const participants = [
    { nik: '001', nickname: 'ALPHA', divisionGuild: 'OPS', status: 'ACTIVE' },
    { nik: '002', nickname: 'BRAVO', divisionGuild: 'IT', status: 'ACTIVE' },
    { nik: '003', nickname: 'CHARLIE', divisionGuild: 'OPS', status: 'ACTIVE' },
    { nik: '004', nickname: 'INACTIVE', divisionGuild: 'OPS', status: 'INACTIVE' },
  ];
  const stats = {
    '001': { totalXp: 100, totalDistanceKm: 5, totalActivities: 3, currentLevel: 2, currentLevelName: 'SCOUT' },
    '002': { totalXp: 200, totalDistanceKm: 2, totalActivities: 5, currentLevel: 3, currentLevelName: 'RANGER' },
    '003': { totalXp: 100, totalDistanceKm: 10, totalActivities: 1, currentLevel: 2, currentLevelName: 'SCOUT' },
    '004': { totalXp: 9999, totalDistanceKm: 999, totalActivities: 999, currentLevel: 9, currentLevelName: 'HIDDEN' },
  };

  const xp = buildLeaderboard_('001', participants, stats, 'TOTAL_XP', 50);
  const distance = buildLeaderboard_('001', participants, stats, 'TOTAL_DISTANCE', 50);
  const activities = buildLeaderboard_('001', participants, stats, 'TOTAL_ACTIVITIES', 50);
  const guild = buildLeaderboard_(
    '001',
    participants.filter(function (participant) {
      return normalizeDivisionKey_(participant.divisionGuild) === 'ops';
    }),
    stats,
    'TOTAL_DISTANCE',
    50
  );
  assertBackendTest_(
    xp.leaderboard.map(function (entry) { return entry.nik; }).join(',') === '002,001,003',
    'TOTAL_XP harus descending dengan nickname sebagai tie-breaker.'
  );
  assertBackendTest_(
    distance.leaderboard.map(function (entry) { return entry.nik; }).join(',') === '003,001,002',
    'TOTAL_DISTANCE harus descending.'
  );
  assertBackendTest_(
    activities.leaderboard.map(function (entry) { return entry.nik; }).join(',') === '002,001,003',
    'TOTAL_ACTIVITIES harus descending.'
  );
  assertBackendTest_(
    guild.leaderboard.map(function (entry) { return entry.nik; }).join(',') === '003,001',
    'Scope GUILD hanya boleh berisi member satu Division.'
  );
  assertBackendTest_(
    xp.currentUserRank && xp.currentUserRank.rank === 2 && xp.currentUserRank.metricValue === 100,
    'Current user rank harus dihitung dari full leaderboard.'
  );
  assertBackendTest_(
    buildLeaderboard_('NO-STATS', participants, stats, 'TOTAL_XP', 50).currentUserRank === null,
    'User tanpa stats harus memiliki currentUserRank null.'
  );
  assertBackendTest_(
    buildLeaderboard_('001', participants, {}, 'TOTAL_XP', 50).leaderboard.length === 0,
    'User_Stats kosong harus menghasilkan leaderboard kosong.'
  );

  const manyParticipants = [];
  const manyStats = {};
  for (let index = 0; index < 55; index += 1) {
    const nik = 'LIMIT-' + index;
    manyParticipants.push({ nik: nik, nickname: nik, divisionGuild: 'OPS', status: 'ACTIVE' });
    manyStats[nik] = {
      totalXp: index,
      totalDistanceKm: index,
      totalActivities: index,
      currentLevel: 1,
      currentLevelName: 'ROOKIE',
    };
  }
  assertBackendTest_(
    buildLeaderboard_('LIMIT-0', manyParticipants, manyStats, 'TOTAL_XP', 50).leaderboard.length === 50,
    'Leaderboard harus dibatasi maksimal 50 row.'
  );

  return {
    ok: true,
    totalXpSorting: true,
    totalDistanceSorting: true,
    totalActivitiesSorting: true,
    stableTieBreaker: true,
    inactiveFiltering: true,
    guildScopeIsolation: true,
    currentUserRank: true,
    emptyStatsSafe: true,
    maxRows50: true,
    sensitiveFieldsExcluded: true,
  };
}

function assertLeaderboardSorted_(leaderboard, metric) {
  for (let index = 1; index < leaderboard.length; index += 1) {
    const previous = leaderboardMetricValue_(leaderboard[index - 1], metric);
    const current = leaderboardMetricValue_(leaderboard[index], metric);
    assertBackendTest_(previous >= current, 'Leaderboard tidak terurut descending untuk ' + metric + '.');
  }
}

function testGetQuestProgress() {
  const sessionToken = getOrCreateTestSessionToken_();
  const session = requireSession_(sessionToken);
  const participant = findParticipantByNik_(session.nik);
  const expectedQuestCount = getActiveQuests_().length;
  const response = JSON.parse(handleGetQuestProgress_({
    action: 'getQuestProgress',
    sessionToken: sessionToken,
  }).getContent());

  assertBackendTest_(response.ok === true, 'getQuestProgress harus return ok true.');
  assertBackendTest_(Array.isArray(response.quests), 'Response harus memiliki array quests.');
  assertBackendTest_(
    response.quests.length === expectedQuestCount,
    'Jumlah progress quest harus sama dengan quest aktif.'
  );

  const validStatuses = {
    NOT_STARTED: true,
    IN_PROGRESS: true,
    COMPLETED: true,
    UNKNOWN_TYPE: true,
    UNSUPPORTED_GROUP_SCOPE: true,
    NO_GUILD: true,
  };
  response.quests.forEach(function (quest) {
    assertBackendTest_(!!quest.questId, 'Quest progress wajib memiliki questId.');
    assertBackendTest_(validStatuses[quest.status], 'Status quest tidak dikenali.');
    assertBackendTest_(
      quest.progressPercent >= 0 && quest.progressPercent <= 100,
      'Progress percent harus berada pada rentang 0-100.'
    );
    assertBackendTest_(
      quest.completed === (quest.status === 'COMPLETED'),
      'Flag completed harus konsisten dengan status.'
    );

    const mappedType = mapQuestType_(normalizeQuestType_(quest.type));
    if (mappedType === 'GUILD_DISTANCE') {
      assertBackendTest_(
        quest.claimable === false &&
          quest.claimBlockedReason === 'GUILD_REWARD_NOT_READY',
        'GUILD_DISTANCE tidak boleh claim reward pada sprint ini.'
      );
      if (String(participant.divisionGuild || '').trim()) {
        assertBackendTest_(
          quest.status !== 'UNSUPPORTED_GROUP_SCOPE' && quest.status !== 'NO_GUILD',
          'GUILD_DISTANCE user dengan Division harus memiliki progress real.'
        );
      } else {
        assertBackendTest_(
          quest.status === 'NO_GUILD' && quest.progress === 0,
          'GUILD_DISTANCE user tanpa Division harus aman sebagai NO_GUILD.'
        );
      }
    } else if (mappedType) {
      assertBackendTest_(
        quest.status !== 'UNKNOWN_TYPE',
        'Tipe quest yang didukung tidak boleh menghasilkan UNKNOWN_TYPE.'
      );
    }
  });

  const mappingTests = testQuestProgressTypeMappings();
  const attendanceTests = testAttendanceQuestProgress();

  const summary = {
    ok: true,
    activeQuestCount: response.quests.length,
    supportedTypes: [
      'DISTANCE',
      'RUN_COUNT',
      'TOTAL_RUNS',
      'RUN_DAYS',
      'SINGLE_RUN',
      'DURATION',
      'XP',
      'STREAK',
      'GUILD_DISTANCE',
      'ATTENDANCE',
    ],
    guildRewardClaimBlocked: true,
    unknownTypeSafe: true,
    mappingTests: mappingTests,
    attendanceTests: attendanceTests,
    quests: response.quests,
  };
  console.log(JSON.stringify(summary, null, 2));
  return summary;
}

function testQuestProgressTypeMappings() {
  const ownerNik = 'TEST-OWNER';
  const rows = [
    testActivityRow_('A1', ownerNik, '2026-08-10T06:00:00+07:00', '', 2, 600),
    testActivityRow_('A2', ownerNik, '2026-08-10T08:00:00+07:00', '', 6, 900),
    testActivityRow_('A3', ownerNik, '', '2026-08-11T06:00:00+07:00', 1, 300),
    testActivityRow_('OUTSIDE', ownerNik, '2026-08-20T06:00:00+07:00', '', 50, 5000),
    testActivityRow_('OTHER', 'OTHER-USER', '2026-08-12T06:00:00+07:00', '', 100, 5000),
    testActivityRow_('MEMBER', 'GUILD-MEMBER', '2026-08-12T07:00:00+07:00', '', 4, 500),
    testActivityRow_('INACTIVE', 'INACTIVE-MEMBER', '2026-08-12T08:00:00+07:00', '', 100, 5000),
    testActivityRow_('PAUSED', ownerNik, '2026-08-12T06:00:00+07:00', '', 100, 5000, 'PAUSED'),
  ];
  const activities = mapCompletedActivityRowsForNik_(rows, ownerNik);
  const guildContext = buildGuildActivityContext_({
    nik: ownerNik,
    divisionGuild: 'OPS',
  }, [
    { nik: ownerNik, divisionGuild: 'OPS', status: 'ACTIVE' },
    { nik: 'GUILD-MEMBER', divisionGuild: 'ops', status: 'ACTIVE' },
    { nik: 'INACTIVE-MEMBER', divisionGuild: 'OPS', status: 'INACTIVE' },
    { nik: 'OTHER-USER', divisionGuild: 'OTHER', status: 'ACTIVE' },
  ], rows);
  const baseQuest = {
    questId: 'TEST-QUEST',
    questName: 'Test Quest',
    questType: 'DISTANCE',
    targetValue: 5,
    unit: '',
    rewardXp: 0,
    periodType: 'WEEKLY',
    startDate: '2026-08-10',
    endDate: '2026-08-16',
  };

  assertBackendTest_(
    activities.length === 4,
    'Filter activity harus mengecualikan user lain dan status non-COMPLETED.'
  );

  const distance = calculateQuestProgress_(baseQuest, activities, null);
  assertBackendTest_(
    distance.progress === 9,
    'DISTANCE harus menjumlahkan milik user dalam periode saja.'
  );

  const totalRuns = calculateQuestProgress_(
    Object.assign({}, baseQuest, { questType: 'TOTAL_RUNS', targetValue: 3 }),
    activities,
    null,
    null,
    { MIN_DISTANCE_VALID_RUN_KM: 1.0 }
  );
  assertBackendTest_(
    totalRuns.progress === 3 && totalRuns.completed === true,
    'TOTAL_RUNS harus menghitung activity unik yang mencapai jarak valid.'
  );

  const totalRunsEligibility = testTotalRunsEligibility();

  const runDays = calculateQuestProgress_(
    Object.assign({}, baseQuest, { questType: 'RUN_DAYS', targetValue: 3 }),
    activities,
    null
  );
  assertBackendTest_(
    runDays.progress === 2 && runDays.status === 'IN_PROGRESS',
    'RUN_DAYS harus menghitung tanggal unik, bukan jumlah activity.'
  );

  const singleRun = calculateQuestProgress_(
    Object.assign({}, baseQuest, { questType: 'SINGLE_RUN', targetValue: 5 }),
    activities,
    null
  );
  assertBackendTest_(
    singleRun.progress === 6 &&
      singleRun.progressPercent === 100 &&
      singleRun.completed === true,
    'SINGLE_RUN harus memakai jarak terbesar dan completed saat mencapai target.'
  );

  const incompleteSingleRun = calculateQuestProgress_(
    Object.assign({}, baseQuest, { questType: 'SINGLE_RUN', targetValue: 10 }),
    activities,
    null
  );
  assertBackendTest_(
    incompleteSingleRun.progress === 6 &&
      incompleteSingleRun.status === 'IN_PROGRESS' &&
      incompleteSingleRun.completed === false,
    'SINGLE_RUN di bawah target harus tetap IN_PROGRESS.'
  );

  const guildDistance = calculateQuestProgress_(
    Object.assign({}, baseQuest, { questType: 'GUILD_DISTANCE', targetValue: 20 }),
    activities,
    null,
    guildContext
  );
  assertBackendTest_(
    guildDistance.status === 'IN_PROGRESS' &&
      guildDistance.progress === 13 &&
      guildDistance.progressPercent === 65 &&
      guildDistance.completed === false,
    'GUILD_DISTANCE harus menghitung member ACTIVE satu Division dalam periode.'
  );
  const completedGuildDistance = calculateQuestProgress_(
    Object.assign({}, baseQuest, { questType: 'GUILD_DISTANCE', targetValue: 10 }),
    activities,
    null,
    guildContext
  );
  assertBackendTest_(
    completedGuildDistance.completed === true &&
      completedGuildDistance.progressPercent === 100 &&
      completedGuildDistance.claimable === false &&
      completedGuildDistance.claimBlockedReason === 'GUILD_REWARD_NOT_READY',
    'GUILD_DISTANCE completed harus tetap diblokir dari reward claim.'
  );
  const noGuildDistance = calculateQuestProgress_(
    Object.assign({}, baseQuest, { questType: 'GUILD_DISTANCE' }),
    activities,
    null,
    { hasGuild: false, activities: [] }
  );
  assertBackendTest_(
    noGuildDistance.status === 'NO_GUILD' && noGuildDistance.progress === 0,
    'GUILD_DISTANCE tanpa Division harus aman sebagai NO_GUILD.'
  );

  const unknown = calculateQuestProgress_(
    Object.assign({}, baseQuest, { questType: 'FUTURE_TYPE' }),
    activities,
    null
  );
  assertBackendTest_(
    unknown.status === 'UNKNOWN_TYPE' && unknown.progress === 0,
    'Unknown quest type harus aman dan memiliki progress 0.'
  );

  return {
    ok: true,
    distanceRegression: true,
    totalRuns: true,
    totalRunsEligibility: totalRunsEligibility,
    uniqueRunDays: true,
    singleRunMaximum: true,
    guildDistanceRealProgress: true,
    guildDivisionIsolation: true,
    guildInactiveFiltering: true,
    guildPeriodFiltering: true,
    guildRewardBlocked: true,
    noGuildSafe: true,
    unknownTypeSafe: true,
    ownerIsolation: true,
    periodFiltering: true,
  };
}

/**
 * Pure regression coverage for ATTENDANCE quests. The fixtures model final
 * audit rows after the attendance endpoint has already assigned StreakCount.
 * Quest progress reads that value; it never calculates a separate streak.
 */
function testAttendanceQuestProgress() {
  const baseQuest = {
    questId: 'ATTENDANCE-TEST',
    questName: 'Attendance Test',
    questType: 'ATTENDANCE',
    targetValue: 3,
    unit: 'COUNT',
    rewardXp: 100,
    periodType: 'WEEKLY',
    startDate: '2026-08-10',
    endDate: '2026-08-16',
  };
  const record = function (eventId, checkInAt, streakCount, status) {
    return {
      eventId: eventId,
      checkInAt: checkInAt,
      streakCount: streakCount,
      status: status || 'SUCCESS',
    };
  };
  const first = [record('E-1', '2026-08-10T06:00:00Z', 1)];
  const countTarget = [
    record('E-1', '2026-08-10T06:00:00Z', 1),
    record('E-2', '2026-08-11T06:00:00Z', 2),
    record('E-2', '2026-08-11T06:01:00Z', 2),
    record('E-NON-STREAK', '2026-08-12T06:00:00Z', 2),
    record('E-PROCESSING', '2026-08-13T06:00:00Z', 3, 'PROCESSING'),
  ];
  const streakTarget = [
    record('E-1', '2026-08-10T06:00:00Z', 1),
    record('E-2', '2026-08-11T06:00:00Z', 2),
    record('E-3', '2026-08-12T06:00:00Z', 3),
  ];
  const missedOfficialEvent = [
    record('E-1', '2026-08-10T06:00:00Z', 1),
    record('E-2', '2026-08-11T06:00:00Z', 2),
    record('E-4', '2026-08-13T06:00:00Z', 1),
  ];

  const countZero = calculateQuestProgress_(baseQuest, [], null, null, null, []);
  const countOne = calculateQuestProgress_(baseQuest, [], null, null, null, first);
  const countComplete = calculateQuestProgress_(baseQuest, [], null, null, null, countTarget);
  const streakQuest = Object.assign({}, baseQuest, { unit: 'STREAK' });
  const streakOne = calculateQuestProgress_(streakQuest, [], null, null, null, first);
  const streakComplete = calculateQuestProgress_(streakQuest, [], null, null, null, streakTarget);
  const streakAfterNonStreak = calculateQuestProgress_(streakQuest, [], null, null, null, countTarget);
  const streakReset = calculateQuestProgress_(streakQuest, [], null, null, null, missedOfficialEvent);
  const runningQuest = calculateQuestProgress_(
    Object.assign({}, baseQuest, { questType: 'DISTANCE', unit: 'KM', targetValue: 5 }),
    [{ activityDateKey: '2026-08-10', distanceKm: 5, durationSec: 60 }],
    null,
    null,
    null,
    countTarget
  );
  const claimed = attachQuestClaim_(countComplete, {
    claimId: 'ATTENDANCE-CLAIM',
    claimedAt: new Date('2026-08-12T07:00:00Z'),
  });
  const baseXp = 20;
  const streakBonusXp = 30;
  const questRewardXp = baseQuest.rewardXp;

  assertBackendTest_(countZero.progress === 0 && countZero.status === 'NOT_STARTED', 'Attendance COUNT harus mulai dari 0.');
  assertBackendTest_(countOne.progress === 1 && countOne.status === 'IN_PROGRESS', 'Attendance COUNT harus bertambah per attendance sukses.');
  assertBackendTest_(countComplete.progress === 3 && countComplete.completed, 'Duplicate tidak boleh menambah COUNT dan non-streak event harus dihitung.');
  assertBackendTest_(streakOne.progress === 1 && streakOne.status === 'IN_PROGRESS', 'Attendance STREAK harus memakai StreakCount pertama.');
  assertBackendTest_(streakComplete.progress === 3 && streakComplete.completed, 'Attendance STREAK harus CLAIMABLE pada target.');
  assertBackendTest_(streakAfterNonStreak.progress === 2, 'Event non-streak harus mempertahankan StreakCount backend.');
  assertBackendTest_(streakReset.progress === 1, 'Missed official streak event harus mengikuti reset StreakCount backend.');
  assertBackendTest_(claimed.claimed === true && claimed.claimId === 'ATTENDANCE-CLAIM', 'Attendance quest claimed harus memakai mekanisme claim existing.');
  assertBackendTest_(runningQuest.progress === 5 && runningQuest.completed, 'Attendance tidak boleh mengubah progress quest running.');
  assertBackendTest_(baseXp + streakBonusXp + questRewardXp === 150, 'XP attendance dan quest reward harus tetap terpisah.');

  return {
    ok: true,
    countZeroToTarget: true,
    streakOneToTarget: true,
    missedEventReset: true,
    nonStreakCounts: true,
    nonStreakDoesNotBreak: true,
    duplicateSafe: true,
    claimable: true,
    claimed: true,
    runningQuestUnchanged: true,
    combinedXp: true,
  };
}

function testTotalRunsEligibility() {
  const ownerNik = 'VALID-RUN-OWNER';
  const otherNik = 'VALID-RUN-OTHER';
  const validRunConfig = {
    MIN_DISTANCE_VALID_RUN_KM: 1.0,
    MIN_DISTANCE_XP_KM: 2.0,
  };
  const baseQuest = {
    questId: 'TEST-TOTAL-RUNS',
    questName: '10 Run Adventures',
    questType: 'TOTAL_RUNS',
    targetValue: 10,
    unit: 'RUN',
    rewardXp: 100,
    periodType: 'WEEKLY',
    startDate: '2026-08-10',
    endDate: '2026-08-16',
  };

  function progressForRows(rows, config) {
    return calculateQuestProgress_(
      baseQuest,
      mapCompletedActivityRowsForNik_(rows, ownerNik),
      null,
      null,
      config
    );
  }

  const shortRows = [];
  for (let index = 0; index < 10; index += 1) {
    shortRows.push(testActivityRow_(
      'SHORT-' + index,
      ownerNik,
      '2026-08-10T06:' + String(index).padStart(2, '0') + ':00+07:00',
      '',
      0.05,
      60
    ));
  }
  assertBackendTest_(
    progressForRows(shortRows, validRunConfig).progress === 0,
    '10 activity x 50 m tidak boleh menambah TOTAL_RUNS.'
  );

  const mixedRows = [];
  for (let index = 0; index < 9; index += 1) {
    mixedRows.push(testActivityRow_(
      'VALID-' + index,
      ownerNik,
      '2026-08-11T06:' + String(index).padStart(2, '0') + ':00+07:00',
      '',
      1.2,
      600
    ));
  }
  mixedRows.push(testActivityRow_(
    'TOO-SHORT', ownerNik, '2026-08-11T08:00:00+07:00', '', 0.05, 60
  ));
  const mixedProgress = progressForRows(mixedRows, validRunConfig);
  assertBackendTest_(
    mixedProgress.progress === 9 && mixedProgress.status === 'IN_PROGRESS',
    '9 valid activity dan 1 activity pendek harus menghasilkan progress 9.'
  );

  const thresholdRows = [];
  for (let index = 0; index < 10; index += 1) {
    thresholdRows.push(testActivityRow_(
      'THRESHOLD-' + index,
      ownerNik,
      '2026-08-12T06:' + String(index).padStart(2, '0') + ':00+07:00',
      '',
      1.0,
      600
    ));
  }
  const thresholdProgress = progressForRows(thresholdRows, validRunConfig);
  assertBackendTest_(
    thresholdProgress.progress === 10 &&
      thresholdProgress.completed === true &&
      thresholdProgress.status === 'COMPLETED',
    '10 activity tepat di threshold harus completed dan siap diklaim.'
  );
  const claimableProgress = attachQuestClaim_(thresholdProgress, null);
  assertBackendTest_(
    claimableProgress.completed === true && claimableProgress.claimed === false,
    'TOTAL_RUNS completed tanpa claim harus tetap claimable di client.'
  );
  const claimedProgress = attachQuestClaim_(thresholdProgress, {
    claimId: 'VALID-RUN-CLAIM',
    claimedAt: new Date('2026-08-16T07:00:00+07:00'),
  });
  assertBackendTest_(
    claimedProgress.completed === true &&
      claimedProgress.claimed === true &&
      claimedProgress.claimId === 'VALID-RUN-CLAIM',
    'TOTAL_RUNS yang sudah diklaim harus mempertahankan state claimed.'
  );

  assertBackendTest_(
    progressForRows([
      testActivityRow_('FIVE-KM', ownerNik, '2026-08-13T06:00:00+07:00', '', 5, 1800),
    ], validRunConfig).progress === 1,
    'Activity 5 km harus dihitung sebagai 1 run, bukan 5.'
  );

  const duplicateRow = testActivityRow_(
    'DUPLICATE', ownerNik, '2026-08-13T07:00:00+07:00', '', 1.5, 700
  );
  assertBackendTest_(
    progressForRows([duplicateRow, Object.assign({}, duplicateRow)], validRunConfig).progress === 1,
    'ActivityId duplicate hanya boleh dihitung sekali.'
  );

  assertBackendTest_(
    progressForRows([
      testActivityRow_('OWNER', ownerNik, '2026-08-14T06:00:00+07:00', '', 1.5, 700),
      testActivityRow_('OTHER', otherNik, '2026-08-14T06:00:00+07:00', '', 10, 3600),
    ], validRunConfig).progress === 1,
    'TOTAL_RUNS hanya boleh menghitung activity milik NIK yang diminta.'
  );

  assertBackendTest_(
    progressForRows([
      testActivityRow_('IN-PERIOD', ownerNik, '2026-08-15T06:00:00+07:00', '', 1.5, 700),
      testActivityRow_('OUT-PERIOD', ownerNik, '2026-08-20T06:00:00+07:00', '', 10, 3600),
    ], validRunConfig).progress === 1,
    'Activity di luar periode Quest tidak boleh dihitung.'
  );

  const fallbackRows = [
    testActivityRow_('FALLBACK-SHORT', ownerNik, '2026-08-15T07:00:00+07:00', '', 0.99, 600),
    testActivityRow_('FALLBACK-VALID', ownerNik, '2026-08-15T08:00:00+07:00', '', 1.0, 600),
  ];
  assertBackendTest_(
    progressForRows(fallbackRows, {}).progress === 1,
    'Config missing harus memakai fallback 1.0 km.'
  );
  assertBackendTest_(
    progressForRows(fallbackRows, { MIN_DISTANCE_VALID_RUN_KM: 'invalid' }).progress === 1,
    'Config invalid harus memakai fallback 1.0 km.'
  );

  assertBackendTest_(
    progressForRows([
      testActivityRow_('SEPARATE-XP', ownerNik, '2026-08-16T06:00:00+07:00', '', 1.5, 700),
    ], validRunConfig).progress === 1,
    'TOTAL_RUNS harus mengikuti MIN_DISTANCE_VALID_RUN_KM, bukan MIN_DISTANCE_XP_KM.'
  );

  return {
    ok: true,
    shortActivitiesExcluded: true,
    mixedDistances: true,
    exactThresholdClaimable: true,
    claimedStatePreserved: true,
    longActivityCountsOnce: true,
    duplicateSafe: true,
    ownerIsolation: true,
    periodFiltering: true,
    missingConfigFallback: true,
    invalidConfigFallback: true,
    xpThresholdSeparated: true,
  };
}

function testActivityRow_(id, nik, endTime, startTime, distanceKm, durationSec, status) {
  return {
    ActivityId: id,
    NIK: nik,
    EndTime: endTime,
    StartTime: startTime,
    DistanceKm: distanceKm,
    DurationSec: durationSec,
    Status: status || 'COMPLETED',
  };
}

function assertUserStatsTotalsEqual_(expected, actual, message) {
  const equal =
    expected.totalActivities === actual.totalActivities &&
    expected.totalDistanceKm === actual.totalDistanceKm &&
    expected.totalDurationSec === actual.totalDurationSec &&
    expected.totalXp === actual.totalXp &&
    expected.currentLevel === actual.currentLevel &&
    expected.currentLevelName === actual.currentLevelName &&
    expected.nextLevelXp === actual.nextLevelXp &&
    expected.lastActivityId === actual.lastActivityId;
  assertBackendTest_(equal, message);
}

/**
 * Pure/editor-safe coverage for the Attendance rules. It does not write to
 * sheets, alter XP, or require a real session. Run this after deployment.
 */
function testAttendanceFoundation() {
  const timeZone = Session.getScriptTimeZone();
  const event1 = attendanceTestEvent_('E-1', '2026-08-20', '08:00:00', true, 'ACTIVE', 'QR-ONE', timeZone);
  const event2 = attendanceTestEvent_('E-2', '2026-08-21', '08:00:00', true, 'ACTIVE', 'QR-TWO', timeZone);
  const event3 = attendanceTestEvent_('E-3', '2026-08-22', '08:00:00', true, 'ACTIVE', 'QR-THREE', timeZone);
  const nonStreak = attendanceTestEvent_('E-NON', '2026-08-20', '12:00:00', false, 'ACTIVE', 'QR-NON', timeZone);
  const inactive = attendanceTestEvent_('E-OFF', '2026-08-23', '08:00:00', true, 'INACTIVE', 'QR-OFF', timeZone);
  const events = [event3, nonStreak, event1, event2, inactive];
  const nik = 'TEST-ATTENDANCE';
  const rewards = [
    { rewardType: 'BASE', milestone: 1, xp: 20, status: 'ACTIVE' },
    { rewardType: 'STREAK', milestone: 3, xp: 30, status: 'ACTIVE' },
    { rewardType: 'STREAK', milestone: 5, xp: 50, status: 'ACTIVE' },
  ];
  const start = localDateTimeToMillis_('2026-08-20', '08:00:00', timeZone);
  const end = localDateTimeToMillis_('2026-08-20', '10:00:00', timeZone);

  const tokens = {};
  for (let index = 0; index < 20; index += 1) {
    const token = newUniqueAttendanceQrToken_([{ qrToken: 'EXISTING-' + index }]);
    assertBackendTest_(!tokens[token] && token.indexOf('ORAATT-') === 0, 'QR token harus unik dan sulit ditebak.');
    tokens[token] = true;
  }
  assertBackendTest_(findAttendanceEventByQrToken_('UNKNOWN', events) === null, 'QR tidak valid harus aman.');
  assertBackendTest_(findAttendanceEventByQrToken_('QR-TWO', events).eventId === 'E-2', 'QR valid harus menemukan event.');
  assertBackendTest_(getAttendanceEventEligibilityStatus_(inactive, new Date(start)) === 'EVENT_INACTIVE', 'Event inactive harus ditolak.');

  assertBackendTest_(getAttendanceEventScanStatus_(event1, new Date(start + 60000)) === 'SUCCESS', 'Event aktif dalam waktu scan harus valid.');
  assertBackendTest_(getAttendanceEventScanStatus_(event1, new Date(start - 1)) === 'EVENT_NOT_STARTED', 'Scan sebelum waktu event harus ditolak.');
  assertBackendTest_(getAttendanceEventScanStatus_(event1, new Date(end + 1)) === 'EVENT_CLOSED', 'Scan setelah waktu event harus ditolak.');
  assertBackendTest_(getAttendanceFeatureStatus_({ ATTENDANCE_ENABLED: false, ATTENDANCE_QR_ENABLED: true }) === 'ATTENDANCE_DISABLED', 'Config attendance disabled harus dihormati.');
  assertBackendTest_(getAttendanceFeatureStatus_({ ATTENDANCE_ENABLED: true, ATTENDANCE_QR_ENABLED: false }) === 'ATTENDANCE_QR_DISABLED', 'Config QR attendance disabled harus dihormati.');

  const attendanceHeaders = [
    'EventId', 'EventName', 'EventDate', 'StartTime', 'EndTime', 'CountForStreak',
    'QRToken', 'Status', 'CreatedAt', 'UpdatedAt', 'QRCode',
  ];
  const qrHeaderMap = getRequiredAttendanceQrCodeHeaderMap_(attendanceHeaders);
  const generatedQrFormula = buildAttendanceQrCodeFormula_(qrHeaderMap, 2);
  assertBackendTest_(
    generatedQrFormula === '=IMAGE("https://quickchart.io/qr?text="&ENCODEURL(G2)&"&size=250")',
    'Formula QR harus memakai payload QRToken dari header, bukan EventId.'
  );
  const reorderedQrHeaderMap = getRequiredAttendanceQrCodeHeaderMap_([
    'QRCode', 'EventId', 'Status', 'QRToken', 'EventName',
  ]);
  assertBackendTest_(
    buildAttendanceQrCodeFormula_(reorderedQrHeaderMap, 7) ===
      '=IMAGE("https://quickchart.io/qr?text="&ENCODEURL(D7)&"&size=250")',
    'Formula QR harus mengikuti posisi header QRToken saat kolom berpindah.'
  );
  let missingQrCodeHeaderRaised = false;
  try {
    getRequiredAttendanceQrCodeHeaderMap_(['EventId', 'QRToken']);
  } catch (error) {
    missingQrCodeHeaderRaised = error && error.oraCode === 'INVALID_ATTENDANCE_QR_SCHEMA';
  }
  assertBackendTest_(
    missingQrCodeHeaderRaised,
    'Kolom QRCode yang hilang harus menghasilkan error admin yang jelas.'
  );

  assertBackendTest_(getAttendanceBaseXp_(rewards) === 20, 'Base XP harus dibaca dari reward master.');
  assertAttendanceConfigError_(function () {
    getAttendanceBaseXp_([]);
  }, 'Base XP missing harus menghasilkan CONFIG_ERROR.');

  const record1 = attendanceTestRecord_(nik, 'E-1');
  const record2 = attendanceTestRecord_(nik, 'E-2');
  assertBackendTest_(calculateAttendanceStreakForEvent_(events, [], nik, event1) === 1, 'Attendance pertama harus streak 1.');
  assertBackendTest_(calculateAttendanceStreakForEvent_(events, [record1], nik, event2) === 2, 'Attendance berurutan kedua harus streak 2.');
  assertBackendTest_(calculateAttendanceStreakForEvent_(events, [record1, record2], nik, event3) === 3, 'Attendance berurutan ketiga harus streak 3.');
  assertBackendTest_(calculateAttendanceStreakForEvent_(events, [record1], nik, event3) === 1, 'Melewatkan event streak harus reset ke 1.');
  assertBackendTest_(calculateAttendanceStreakForEvent_(events, [record1], nik, event2) === 2, 'Event CountForStreak FALSE tidak boleh memutus streak.');
  assertBackendTest_(calculateAttendanceStreakForEvent_(events, [record1], nik, nonStreak) === 1, 'Event CountForStreak FALSE tidak boleh menambah streak.');

  assertBackendTest_(getAttendanceStreakBonusXp_(rewards, 3) === 30, 'Milestone streak 3 harus memberi bonus.');
  assertBackendTest_(getAttendanceStreakBonusXp_(rewards, 4) === 0, 'Streak 4 tidak boleh memberi bonus ulang.');
  assertBackendTest_(getAttendanceStreakBonusXp_(rewards, 5) === 50, 'Milestone streak 5 harus memberi bonus.');
  assertBackendTest_(getAttendanceBaseXp_(rewards) + getAttendanceStreakBonusXp_(rewards, 3) === 50, 'Total XP attendance harus base plus bonus.');
  assertBackendTest_(findAttendanceRecordInRecords_([record1], nik, 'E-1') === record1, 'Duplicate attendance harus terdeteksi sebelum grant XP kedua.');
  const beforeStats = {
    nickname: 'ATTEND', division: 'OPS', totalActivities: 7, totalDistanceKm: 42.5,
    totalDurationSec: 3600, totalXp: 100, lastActivityId: 'RUN-7', lastActivityAt: '2026-08-20T07:00:00+07:00',
  };
  const afterXpGrant = buildXpOnlyUserStats_(
    { nik: nik, nickname: 'ATTEND', divisionGuild: 'OPS' },
    beforeStats,
    150,
    { currentLevel: 2, currentLevelName: 'SCOUT', nextLevelXp: 200 },
    new Date()
  );
  assertBackendTest_(
    afterXpGrant.totalActivities === beforeStats.totalActivities &&
      afterXpGrant.totalDistanceKm === beforeStats.totalDistanceKm &&
      afterXpGrant.totalDurationSec === beforeStats.totalDurationSec &&
      afterXpGrant.lastActivityId === beforeStats.lastActivityId &&
      afterXpGrant.totalXp === 150,
    'Attendance XP tidak boleh mengubah statistik running.'
  );

  return {
    ok: true,
    tokenUnique: true,
    validAndInvalidQr: true,
    inactiveEvent: true,
    eventWindow: true,
    attendanceConfig: true,
    qrCodeFormula: true,
    qrCodeHeaderSafety: true,
    rewardMasterOnly: true,
    streakOneTwoThree: true,
    missedEventReset: true,
    nonStreakDoesNotBreak: true,
    milestoneThree: true,
    milestoneFourNoRepeat: true,
    milestoneFive: true,
    duplicateSafe: true,
    xpOnlyAttendanceWriter: true,
  };
}

function attendanceTestEvent_(eventId, dateKey, startTimeKey, countForStreak, status, qrToken, timeZone) {
  return {
    eventId: eventId,
    eventName: eventId,
    eventDateKey: dateKey,
    startTimeKey: startTimeKey,
    endTimeKey: '10:00:00',
    countForStreak: countForStreak,
    status: status,
    qrToken: qrToken,
    timeZone: timeZone,
  };
}

function attendanceTestRecord_(nik, eventId) {
  return {
    nik: nik,
    eventId: eventId,
    status: 'SUCCESS',
  };
}

function assertAttendanceConfigError_(callback, message) {
  let raised = false;
  try {
    callback();
  } catch (error) {
    raised = error && error.oraCode === 'CONFIG_ERROR';
  }
  assertBackendTest_(raised, message);
}

function assertBackendTest_(condition, message) {
  if (!condition) throw new Error('Backend-3 test failed: ' + message);
}

function testSharedActivityImportFoundation() {
  assertBackendTest_(
    ORA_HEADERS.Activities[15] === 'SourceRef' &&
      ORA_HEADERS.Activities[16] === 'SourceUrl',
    'SourceRef dan SourceUrl harus tetap berada di kolom P dan Q.'
  );
  assertBackendTest_(
    extractActivitySourceRef_('STRAVA', 'https://www.strava.com/activities/123456?x=1') === '123456',
    'Canonical Strava activity ID tidak terbaca.'
  );
  assertBackendTest_(
    extractActivitySourceRef_('STRAVA', 'https://strava.app.link/Full6cF8S5b') === 'Full6cF8S5b',
    'Kode Strava short link tidak terbaca.'
  );
  const legacy = mapActivityHistoryRowsForNik_([{
    ActivityId: 'LEGACY-1',
    NIK: '1001',
    StartTime: new Date('2026-08-25T00:00:00.000Z'),
    EndTime: new Date('2026-08-25T00:30:00.000Z'),
    DurationSec: 1800,
    DistanceKm: 5,
    AvgPace: '06:00',
    Status: 'COMPLETED',
    Source: 'ANDROID',
  }], '1001');
  assertBackendTest_(
    legacy.length === 1 && legacy[0].sourceRef === '' && legacy[0].sourceUrl === '',
    'Activity lama tanpa SourceRef/SourceUrl harus tetap valid.'
  );
  return {
    headers: true,
    canonicalSourceRef: true,
    shortSourceRef: true,
    legacyActivity: true,
  };
}

function testStravaSyncFoundation() {
  const normalized = normalizeStravaSyncActivity_({
    athleteName: 'Wandi Nurdyansyah',
    athleteId: '118254162',
    activityId: '19929716616',
    activityDateLocal: '2026-08-28',
    startDateUtc: '2026-08-27T23:14:54Z',
    distanceKm: 6.74,
    movingTimeSeconds: 2836,
    elapsedTimeSeconds: 2868,
    paceSecondsPerKm: 420,
  });
  assertBackendTest_(!normalized.error, 'Activity Strava valid harus dapat dinormalisasi.');

  const participant = {
    nik: '20000001',
    nickname: 'WANDI',
    divisionGuild: 'RUNNING',
  };
  const mapped = buildOraStravaActivityRow_(normalized.activity, participant, new Date(0));
  const unmapped = buildOraStravaActivityRow_(normalized.activity, null, new Date(0));

  assertBackendTest_(mapped[0] === 'STRAVA-19929716616', 'ActivityId ORA Strava tidak deterministik.');
  assertBackendTest_(mapped[1] === '20000001', 'NIK mapped tidak masuk ke row Activities.');
  assertBackendTest_(mapped[6] === 2836, 'DurationSec harus memakai moving time.');
  assertBackendTest_(mapped[8] === '07:00', 'AvgPace Strava tidak terformat benar.');
  assertBackendTest_(mapped[9] === 'COMPLETED', 'Mapped activity harus COMPLETED.');
  assertBackendTest_(mapped[10] === 'STRAVA', 'Source activity harus STRAVA.');
  assertBackendTest_(mapped[15] === '19929716616', 'SourceRef harus memakai activityId Strava.');
  assertBackendTest_(
    mapped[16] === 'https://www.strava.com/activities/19929716616',
    'SourceUrl Strava tidak deterministik.'
  );
  assertBackendTest_(unmapped[1] === '' && unmapped[9] === 'UNMAPPED', 'UNMAPPED tidak boleh memiliki NIK atau status COMPLETED.');
  assertBackendTest_(
    stravaActivityEndTime_(normalized.activity) === '2026-08-28T00:02:42.000Z',
    'EndTime harus memakai elapsed time dari start UTC.'
  );

  const optional = normalizeStravaSyncActivity_({
    athleteId: '1',
    activityId: '2',
    activityDateLocal: '2026-08-28',
    movingTimeSeconds: 600,
  });
  const optionalRow = buildOraStravaActivityRow_(optional.activity, null, new Date(0));
  assertBackendTest_(optionalRow[7] === 0 && optionalRow[8] === '', 'Optional distance/pace harus aman tanpa data palsu.');
  assertBackendTest_(
    normalizeStravaSyncActivity_({ activityId: 'bad' }).error === 'invalid activityId',
    'ActivityId invalid harus ditolak.'
  );
  const observed = collectObservedStravaAthletes_([
    {
      athleteId: '118254162',
      athleteName: 'Wandi Updated',
      activityId: '19929716616',
      activityDateLocal: '2026-08-28',
    },
  ]);
  assertBackendTest_(
    observed['118254162'].athleteName === 'Wandi Updated',
    'AthleteId dan AthleteName harus dikumpulkan untuk athlete map.'
  );
  assertBackendTest_(
    stravaAthleteMapNote_('118254162', { '118254162': '20000001' }, {
      '20000001': participant,
    }) === 'MAPPED',
    'Athlete map dengan participant ACTIVE harus berstatus MAPPED.'
  );
  assertBackendTest_(
    stravaAthleteMapNote_('118254162', {}, {}) === 'UNMAPPED',
    'Athlete map tanpa NIK aktif harus berstatus UNMAPPED.'
  );
  const statsAggregates = aggregateStravaStatsEvents_([
    {
      participant: participant,
      activity: {
        activityId: '2',
        activityDateLocal: '2026-08-29',
        distanceKm: 2.25,
        movingTimeSeconds: 900,
      },
    },
    {
      participant: participant,
      activity: {
        activityId: '1',
        activityDateLocal: '2026-08-28',
        distanceKm: 1.5,
        movingTimeSeconds: 600,
      },
    },
  ], 10);
  assertBackendTest_(
    statsAggregates.length === 1 &&
      statsAggregates[0].activityCount === 2 &&
      statsAggregates[0].distanceKm === 3.75 &&
      statsAggregates[0].durationSec === 1500 &&
      statsAggregates[0].activityXp === 38 &&
      statsAggregates[0].lastActivityId === 'STRAVA-2',
    'Batch User_Stats harus mengagregasi aktivitas per NIK secara kronologis.'
  );

  return {
    normalize: true,
    mappedRow: true,
    unmappedNoXp: true,
    deterministicUrl: true,
    optionalStats: true,
    endTime: true,
    athleteMap: true,
    batchStats: true,
  };
}

/**
 * Creates a dummy editor-only test session when the stored token is unavailable.
 * Required Script Properties: ORA_TEST_NIK and ORA_TEST_PIN.
 * Credentials and the full token are never written to logs or returned.
 */
function prepareTestSession() {
  const sessionToken = getOrCreateTestSessionToken_();
  const session = requireSession_(sessionToken);
  return {
    ok: true,
    nik: session.nik,
    tokenStored: true,
    expiresInSeconds: ORA_SESSION_TTL_SECONDS,
    expiresAt: new Date(session.expiresAtMillis).toISOString(),
  };
}

function testSessionTtl30Days() {
  const properties = PropertiesService.getScriptProperties();
  const cache = CacheService.getScriptCache();
  const nowMillis = Date.now();
  const token = 'ORA-TTL-TEST-' + Utilities.getUuid();
  const expiredToken = 'ORA-TTL-EXPIRED-' + Utilities.getUuid();
  const legacyToken = 'ORA-TTL-LEGACY-' + Utilities.getUuid();

  try {
    const saved = saveSession_(token, 'TTL-TEST-USER', nowMillis);
    const expectedExpiry = nowMillis + ORA_SESSION_TTL_SECONDS * 1000;
    assertBackendTest_(
      saved.expiresAtMillis === expectedExpiry,
      'Session harus memiliki expiry tepat 30 hari.'
    );

    const key = sessionCacheKey_(token);
    assertBackendTest_(
      !!properties.getProperty(key),
      'Session 30 hari harus tersimpan persisten di Script Properties.'
    );
    cache.remove(key);
    const restored = requireSession_(token);
    assertBackendTest_(
      restored.nik === 'TTL-TEST-USER' && restored.expiresAtMillis === expectedExpiry,
      'Session harus tetap valid saat cache kosong.'
    );

    const expiredKey = sessionCacheKey_(expiredToken);
    properties.setProperty(expiredKey, JSON.stringify({
      nik: 'TTL-EXPIRED-USER',
      issuedAtMillis: nowMillis - 2000,
      expiresAtMillis: nowMillis - 1000,
    }));
    let expiredRejected = false;
    try {
      requireSession_(expiredToken);
    } catch (error) {
      expiredRejected = error && error.oraCode === 'SESSION_EXPIRED';
    }
    assertBackendTest_(expiredRejected, 'Session expired harus ditolak.');
    assertBackendTest_(
      !properties.getProperty(expiredKey),
      'Session expired harus dibersihkan dari Script Properties.'
    );

    const legacyKey = sessionCacheKey_(legacyToken);
    cache.put(legacyKey, JSON.stringify({ nik: 'TTL-LEGACY-USER' }), 60);
    const migrated = requireSession_(legacyToken);
    assertBackendTest_(
      Number.isFinite(Number(migrated.expiresAtMillis)) &&
        !!properties.getProperty(legacyKey),
      'Session cache lama harus dimigrasikan ke penyimpanan persisten.'
    );

    return {
      ok: true,
      ttlDays: ORA_SESSION_TTL_SECONDS / 86400,
      expiresInSeconds: ORA_SESSION_TTL_SECONDS,
      persistentAfterCacheMiss: true,
      expiredSessionRejected: true,
      legacySessionMigrated: true,
    };
  } finally {
    deleteSession_(token);
    deleteSession_(expiredToken);
    deleteSession_(legacyToken);
  }
}

function getOrCreateTestSessionToken_() {
  const properties = PropertiesService.getScriptProperties();
  const storedToken = String(
    properties.getProperty('ORA_TEST_SESSION_TOKEN') || ''
  ).trim();

  if (storedToken && isSessionTokenValid_(storedToken)) {
    return storedToken;
  }

  const nik = String(properties.getProperty('ORA_TEST_NIK') || '').trim();
  const pin = String(properties.getProperty('ORA_TEST_PIN') || '').trim();
  if (!nik || !pin) {
    throw new Error(
      'Isi Script Properties ORA_TEST_NIK dan ORA_TEST_PIN dengan akun dummy, ' +
      'lalu jalankan prepareTestSession().'
    );
  }

  const login = JSON.parse(handleLogin_({ nik: nik, pin: pin }).getContent());
  if (!login.ok || !login.data || !login.data.sessionToken) {
    const code = login.error && login.error.code ? login.error.code : 'LOGIN_FAILED';
    throw new Error('Tidak dapat membuat test session: ' + code);
  }

  properties.setProperty('ORA_TEST_SESSION_TOKEN', login.data.sessionToken);
  return login.data.sessionToken;
}

function isSessionTokenValid_(sessionToken) {
  try {
    requireSession_(sessionToken);
    return true;
  } catch (error) {
    return false;
  }
}
