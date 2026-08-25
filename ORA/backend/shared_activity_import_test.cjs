'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const backendPath = path.join(__dirname, 'Code.gs');
const source = `${fs.readFileSync(backendPath, 'utf8')}
this.__sharedActivityTestResult = testSharedActivityImportFoundation();`;
const context = {console};
vm.createContext(context);
vm.runInContext(source, context, {filename: backendPath});

const result = context.__sharedActivityTestResult;
if (!result || Object.values(result).some((value) => value !== true)) {
  throw new Error('Shared activity import backend test failed.');
}
console.log(`PASS ${JSON.stringify(result)}`);
