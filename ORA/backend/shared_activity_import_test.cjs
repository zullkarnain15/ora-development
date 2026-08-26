'use strict';

const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const backendPath = path.join(__dirname, 'Code.gs');
const source = `${fs.readFileSync(backendPath, 'utf8')}
this.__sharedActivityTestResult = testSharedActivityImportFoundation();
this.__shortcutLinkTestResult = {
  valid: normalizeIphoneShortcutLink_(
    '  https://www.icloud.com/shortcuts/30c3fe6ba4ef4381ba5e75019c150768  '
  ) === 'https://www.icloud.com/shortcuts/30c3fe6ba4ef4381ba5e75019c150768',
  rejectsOtherHost: false,
};
try {
  normalizeIphoneShortcutLink_('https://example.com/shortcuts/wrong');
} catch (error) {
  this.__shortcutLinkTestResult.rejectsOtherHost =
    error && error.oraCode === 'SHORTCUT_LINK_INVALID';
}`;
const context = {console};
vm.createContext(context);
vm.runInContext(source, context, {filename: backendPath});

const result = context.__sharedActivityTestResult;
if (!result || Object.values(result).some((value) => value !== true)) {
  throw new Error('Shared activity import backend test failed.');
}
const shortcutResult = context.__shortcutLinkTestResult;
if (!shortcutResult || Object.values(shortcutResult).some((value) => value !== true)) {
  throw new Error('iPhone Shortcut link backend test failed.');
}
console.log(`PASS ${JSON.stringify({...result, ...shortcutResult})}`);
