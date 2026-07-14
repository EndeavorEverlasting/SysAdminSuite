#!/usr/bin/env node
'use strict';

const assert = require('assert');
require('./js/software-deployment-tutorial.js');

const api = global.__sasSoftwareDeploymentTutorialApi;
assert(api, 'software deployment tutorial API was not exposed');

assert(api.DRY_RUN_COMMAND.includes('Invoke-SasSoftwareInstallE2E.ps1'));
assert(api.DRY_RUN_COMMAND.includes('survey\\output\\software-install-e2e'));

const validInput = {
  target: 'WNH269OPR009',
  packageName: "Vendor's Approved Tool",
  installerPath: 'packages\\Vendor\\Package\\setup.exe',
  installerArguments: '/quiet\n/norestart',
  installMode: 'UncDirect'
};

const validation = api.validatePilot(validInput);
assert.strictEqual(validation.valid, true, validation.errors.join('; '));
assert.deepStrictEqual(validation.value.installerArguments, ['/quiet', '/norestart']);

const whatIf = api.buildWhatIfCommand(validInput);
assert.strictEqual(whatIf.valid, true);
assert(whatIf.command.includes("-ComputerName 'WNH269OPR009'"));
assert(whatIf.command.includes("-PackageName 'Vendor''s Approved Tool'"));
assert(whatIf.command.includes("-InstallerArguments @('/quiet', '/norestart')"));
assert(whatIf.command.includes('-InstallMode UncDirect'));
assert(whatIf.command.includes('-WhatIf'));
assert(!whatIf.command.includes('-AllowTargetMutation'));
assert(!whatIf.command.includes('-Confirm:$false'));

const pilot = api.buildPilotCommand({ ...validInput, installMode: 'CopyThenInstall' });
assert.strictEqual(pilot.valid, true);
assert(pilot.command.includes('-InstallMode CopyThenInstall'));
assert(pilot.command.includes('-AllowTargetMutation'));
assert(!pilot.command.includes('-WhatIf'));
assert(!pilot.command.includes('-Confirm:$false'));

for (const badTarget of ['HOST1,HOST2', 'HOST1 HOST2', '*', 'HOST1;HOST2']) {
  const result = api.validatePilot({ ...validInput, target: badTarget });
  assert.strictEqual(result.valid, false, `multi/unsafe target accepted: ${badTarget}`);
}

for (const badPath of [
  '\\\\server\\share\\setup.exe',
  'C:\\packages\\setup.exe',
  '..\\packages\\setup.exe',
  'packages\\..\\setup.exe'
]) {
  const result = api.validatePilot({ ...validInput, installerPath: badPath });
  assert.strictEqual(result.valid, false, `unsafe path accepted: ${badPath}`);
}

const noArgs = api.validatePilot({ ...validInput, installerArguments: '' });
assert.strictEqual(noArgs.valid, false, 'empty silent arguments must fail closed');

console.log('PASS: browser software deployment command and safety runtime smoke');
