/**
 * ORA_SheetSchemas.gs
 * Sheet header definitions for all data sheets in the ORA spreadsheet.
 * Used for schema validation and header mapping.
 */

/**
 * Sheet name constants.
 * Frozen object ensures sheet names remain consistent throughout the application.
 */
const ORA_SHEETS = Object.freeze({
  // Master data sheets
  PARTICIPANTS: 'Participants',
  CONFIG: 'Config',
  LEVELS: 'Level_Master',
  QUESTS: 'Quest_Master',
  GUILD_MASTER: 'Guild_Master',

  // Activity tracking sheets
  ACTIVITIES: 'Activities',
  USER_STATS: 'User_Stats',

  // Reward & progression sheets
  QUEST_CLAIMS: 'Quest_Claims',

  // Attendance system sheets
  ATTENDANCE_EVENTS: 'Attendance_Event_Master',
  ATTENDANCE_RECORDS: 'Attendance_Records',
  ATTENDANCE_REWARDS: 'Attendance_Reward_Master',

  // Integration sheets
  SHORTCUT_ICLOUD: 'Shortcut_Icloud',
  STRAVA_ATHLETE_MAP: 'Strava_Athlete_Map',
});

/**
 * Request-level snapshot sheets.
 * These sheets are snapshotted per request to ensure consistent reads.
 * Schema: { sheetName: true }
 */
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

/**
 * Expected header definitions for each sheet.
 * Used for schema validation during setupBackend1().
 * Schema: { sheetName: [header1, header2, ...] }
 */
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
