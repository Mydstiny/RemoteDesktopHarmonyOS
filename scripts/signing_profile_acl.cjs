'use strict';
// Restricted permissions (ACL) granted by a HarmonyOS signing profile (.p7b).
//
// A permission whose ACL the signing profile does not grant makes `hdc install`
// fail with 9568289 for the whole app. The build therefore declares such a
// permission only when the profile in use lists it under acls.allowed-acls.
// The profile is a PKCS#7 envelope around plain JSON, so the JSON fields can be
// read directly from the bytes.
const fs = require('fs');

const INTERCEPT_INPUT_EVENT = 'ohos.permission.INTERCEPT_INPUT_EVENT';

function allowedAclsFromProfileText(text) {
  const match = /"allowed-acls"\s*:\s*\[([^\]]*)\]/.exec(text);
  if (!match) { return []; }
  return Array.from(match[1].matchAll(/"([^"]+)"/g), (item) => item[1]);
}

function readAllowedAcls(profilePath) {
  return allowedAclsFromProfileText(fs.readFileSync(profilePath).toString('latin1'));
}

/** True only when every given profile grants the ACL; unreadable profiles fail closed. */
function profilesAllowAcl(profilePaths, permission) {
  if (profilePaths.length === 0) { return false; }
  return profilePaths.every((profilePath) => {
    try {
      return readAllowedAcls(profilePath).includes(permission);
    } catch (_error) {
      return false;
    }
  });
}

/** Explicit override for unsigned builds or ACL testing: "1" declares, "0" omits. */
function aclOverride(env, name) {
  const value = env[name];
  if (value === '1') { return true; }
  if (value === '0') { return false; }
  return undefined;
}

module.exports = {
  INTERCEPT_INPUT_EVENT,
  aclOverride,
  allowedAclsFromProfileText,
  profilesAllowAcl,
  readAllowedAcls
};

if (require.main === module) {
  const assert = require('assert');
  if (process.argv.includes('--self-test')) {
    const granted = 'xx{"acls":{"allowed-acls":["ohos.permission.READ_PASTEBOARD","' +
      INTERCEPT_INPUT_EVENT + '"]},"apl":"normal"}yy';
    const notGranted = '{"acls":{"allowed-acls":["ohos.permission.READ_PASTEBOARD"]}}';
    assert.deepStrictEqual(allowedAclsFromProfileText(granted),
      ['ohos.permission.READ_PASTEBOARD', INTERCEPT_INPUT_EVENT]);
    assert.deepStrictEqual(allowedAclsFromProfileText('{"acls":{"allowed-acls":[]}}'), []);
    assert.deepStrictEqual(allowedAclsFromProfileText('no profile json'), []);
    assert.strictEqual(allowedAclsFromProfileText(notGranted).includes(INTERCEPT_INPUT_EVENT), false);
    assert.strictEqual(profilesAllowAcl([], INTERCEPT_INPUT_EVENT), false);
    assert.strictEqual(profilesAllowAcl(['/nonexistent.p7b'], INTERCEPT_INPUT_EVENT), false);
    assert.strictEqual(aclOverride({ X: '1' }, 'X'), true);
    assert.strictEqual(aclOverride({ X: '0' }, 'X'), false);
    assert.strictEqual(aclOverride({}, 'X'), undefined);
    console.log('signing profile ACL: 9 checks passed');
  }
  for (const profilePath of process.argv.slice(2).filter((arg) => !arg.startsWith('--'))) {
    console.log(profilePath + ': ' + JSON.stringify(readAllowedAcls(profilePath)));
  }
}
