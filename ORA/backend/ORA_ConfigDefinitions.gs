/**
 * ORA_ConfigDefinitions.gs
 * Schema definitions for all configuration values stored in the Config sheet.
 * Each definition specifies key, default, type, and description.
 */

/**
 * Configuration definitions for the Config_Master sheet.
 * Frozen object for immutability; definitions are read-only.
 */
const ORA_CONFIG_DEFINITIONS = Object.freeze({
  /**
   * Minimum distance for a run to count as a valid completed activity.
   * Used by TOTAL_RUNS quest type to filter short activities.
   * Example: 1.0 = minimum 1 km
   * Note: Different from MIN_DISTANCE_XP_KM which affects XP calculation.
   */
  MIN_DISTANCE_VALID_RUN_KM: Object.freeze({
    key: 'MIN_DISTANCE_VALID_RUN_KM',
    defaultValue: 1.0,
    dataType: 'NUMBER',
    description: 'Jarak minimum agar satu activity dianggap sebagai valid run untuk aturan berbasis jumlah run. Contoh: 1.0 = minimum 1 km. Berbeda dari MIN_DISTANCE_XP_KM.',
  }),

  /**
   * XP points earned per kilometer of running.
   * Used by all activity-based XP calculations.
   * Example: 10 = 10 XP per km
   */
  XP_PER_KM: Object.freeze({
    key: 'XP_PER_KM',
    defaultValue: 10,
    dataType: 'NUMBER',
    description: 'XP yang diperoleh per kilometer lari. Contoh: 10 = 10 XP/km',
  }),

  /**
   * Maximum length for user nicknames.
   * Used during nickname activation and updates.
   * Example: 8 = maximum 8 characters
   */
  NICKNAME_MAX_LENGTH: Object.freeze({
    key: 'NICKNAME_MAX_LENGTH',
    defaultValue: 8,
    dataType: 'NUMBER',
    description: 'Panjang maksimal nickname yang diizinkan. Contoh: 8 = maksimal 8 karakter',
  }),

  /**
   * Enable or disable the entire attendance feature.
   * When false, all attendance endpoints return ATTENDANCE_DISABLED.
   */
  ATTENDANCE_ENABLED: Object.freeze({
    key: 'ATTENDANCE_ENABLED',
    defaultValue: false,
    dataType: 'BOOLEAN',
    description: 'Aktifkan fitur attendance tracking. Ketika FALSE, semua endpoint attendance ditolak.',
  }),

  /**
   * Enable or disable QR code scanning for attendance.
   * Only applies if ATTENDANCE_ENABLED is true.
   */
  ATTENDANCE_QR_ENABLED: Object.freeze({
    key: 'ATTENDANCE_QR_ENABLED',
    defaultValue: false,
    dataType: 'BOOLEAN',
    description: 'Aktifkan QR code scanning untuk attendance. Memerlukan ATTENDANCE_ENABLED=TRUE.',
  }),
});
