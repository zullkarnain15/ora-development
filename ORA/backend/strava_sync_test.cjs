'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const backendPath = path.join(__dirname, 'Code.gs');
const source = `${fs.readFileSync(backendPath, 'utf8')}
this.__stravaSyncTestResult = testStravaSyncFoundation();`;
const context = {console};
vm.createContext(context);
vm.runInContext(source, context, {filename: backendPath});

const result = context.__stravaSyncTestResult;
if (!result || Object.values(result).some((value) => value !== true)) {
  throw new Error('Strava sync backend test failed.');
}

const rows = [
  ['AthleteId', 'AthleteName', 'NIK', 'Nickname', 'Guild', 'active', 'notes'],
  ['111', 'Old Name', '9001', '', '', '', 'UNMAPPED'],
];
const sheet = {
  getLastRow: () => rows.length,
  getLastColumn: () => rows[0].length,
  getMaxRows: () => 100,
  getMaxColumns: () => rows[0].length,
  insertRowsAfter() {},
  insertColumnsAfter() {},
  getRange(startRow, startColumn, rowCount, columnCount) {
    return {
      getDisplayValues() {
        return Array.from({length: rowCount}, (_, rowOffset) =>
          Array.from({length: columnCount}, (_, columnOffset) =>
            (rows[startRow - 1 + rowOffset] || [])[startColumn - 1 + columnOffset] || ''
          )
        );
      },
      setValues(values) {
        values.forEach((valueRow, rowOffset) => {
          const targetRow = startRow - 1 + rowOffset;
          while (rows.length <= targetRow) rows.push(new Array(rows[0].length).fill(''));
          valueRow.forEach((value, columnOffset) => {
            rows[targetRow][startColumn - 1 + columnOffset] = value;
          });
        });
        return this;
      },
      setNumberFormat() {
        return this;
      },
    };
  },
};

const activities = [
  {athleteId: '111', athleteName: 'Updated Name', activityId: '1', activityDateLocal: '2026-08-28'},
  {athleteId: '222', athleteName: 'New Athlete', activityId: '2', activityDateLocal: '2026-08-28'},
];
const observed = context.upsertObservedStravaAthletes_(sheet, activities);
context.refreshObservedStravaAthleteMap_(
  sheet,
  observed,
  {'111': '9001'},
  {'9001': {nik: '9001'}}
);

if (rows.length !== 3) throw new Error('Athlete map did not append a new athlete.');
if (rows[1][1] !== 'Updated Name' || rows[1][6] !== 'MAPPED') {
  throw new Error('Existing athlete map row was not refreshed as MAPPED.');
}
if (rows[2][0] !== '222' || rows[2][1] !== 'New Athlete' || rows[2][6] !== 'UNMAPPED') {
  throw new Error('New athlete map row was not appended as UNMAPPED.');
}
console.log(`PASS ${JSON.stringify(result)}`);
