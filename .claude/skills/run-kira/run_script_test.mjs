import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const SCRIPT = path.join(ROOT, 'scripts/run.ps1');
const DRIVER = path.join(ROOT, '.claude/skills/run-kira/driver.mjs');
const quote = value => `'${String(value).replaceAll("'", "''")}'`;
const windowsOnly = { skip: process.platform !== 'win32' };

function run(target, { config = {}, args = [], avds = ['test_avd'], env = {}, alive = false } = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), "kira-run-test's-"));
  const manager = path.join(dir, 'fake manager.ps1');
  const configPath = path.join(dir, 'config.json');
  const bin = path.join(dir, 'bin');
  mkdirSync(bin);
  writeFileSync(manager, 'Write-Output ("MUMU:" + ($args -join "|")); $global:LASTEXITCODE = 0');
  writeFileSync(configPath, typeof config === 'string' ? config : JSON.stringify({ MuMuManager: manager, ...config }));
  writeFileSync(path.join(bin, 'emulator.cmd'), '@echo off\r\n' + avds.map(id => `echo ${id}\r\n`).join('') + 'exit /b 0\r\n');
  const setup = `
[Console]::OutputEncoding = [Text.UTF8Encoding]::new();
function global:node {
  [Console]::WriteLine('BACKEND:' + $args[1] + '|' + $env:KIRA_HERDR_BACKEND);
  if ($args[1] -eq 'has') { $global:LASTEXITCODE = ${alive ? 0 : 1}; Write-Output '${alive ? 'ALIVE' : 'DEAD'}'; return }
  [Console]::WriteLine('NODE:' + ($args -join '|'));
  [Console]::WriteLine('DEVICE:' + $env:KIRA_DEVICE);
  [Console]::WriteLine('TARGET:' + $env:KIRA_TARGET);
  $global:LASTEXITCODE = 0;
}
function global:flutter {
  [Console]::WriteLine('FLUTTER:' + ($args -join '|'));
  $global:LASTEXITCODE = 0;
}
function global:adb {
  if ($args[0] -eq 'devices') { Write-Output ('test header'); Write-Output ($env:KIRA_TEST_SERIAL + ' device') }
  elseif ($args[0] -eq '-s') { Write-Output $env:KIRA_TEST_AVD; Write-Output 'OK' }
  else { Write-Output 'connected' }
  $global:LASTEXITCODE = 0;
}
& ${quote(SCRIPT)} ${target || ''} -ConfigPath ${quote(configPath)} ${args.map(a => a.startsWith('-') ? a : quote(a)).join(' ')}
`;
  try {
    return spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-Command', setup], {
      cwd: dir,
      encoding: 'utf8',
      windowsHide: true,
      env: {
        ...process.env,
        PATH: `${bin}${path.delimiter}${process.env.PATH || ''}`,
        COPY_AUTH_KEY: '', KIRA_HERDR_BACKEND: '',
        KIRA_MUMU_MANAGER: '', KIRA_MUMU_INDEX: '', KIRA_MUMU_ADB_ADDR: '', KIRA_EMULATOR_NAME: '',
        KIRA_TEST_SERIAL: 'emulator-5678', KIRA_TEST_AVD: 'test_avd',
        ...env,
      },
      timeout: 10000,
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function success(result) {
  assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
}

test('run.ps1 resolves the driver from its own path even when called outside the repo', windowsOnly, () => {
  const result = run('win');
  success(result);
  assert.ok(result.stdout.includes(`NODE:${DRIVER}|start`));
  assert.match(result.stdout, /DEVICE:windows/);
  assert.match(result.stdout, /TARGET:win/);
  assert.ok(!result.stdout.includes('|--wait'));
});

test('run.ps1 forwards explicit wait and rejects conflicting switches', windowsOnly, () => {
  const result = run('win', { args: ['-Wait'] });
  success(result);
  assert.ok(result.stdout.includes('|start|--wait'));
  const conflict = run('win', { args: ['-Wait', '-NoWait'] });
  assert.notEqual(conflict.status, 0);
  assert.match(conflict.stderr, /不能同时使用/);
});

test('a single installed AVD is selected automatically and launches the exact device', windowsOnly, () => {
  const result = run('emu');
  success(result);
  assert.match(result.stdout, /FLUTTER:emulators\|--launch\|test_avd/);
  assert.match(result.stdout, /DEVICE:emulator-5678/);
  assert.match(result.stdout, /TARGET:emu/);
});

test('multiple or missing AVDs fail before stopping the running app', windowsOnly, () => {
  for (const avds of [[], ['first_avd', 'second_avd']]) {
    const result = run('emu', { avds });
    assert.notEqual(result.status, 0);
    assert.ok(!result.stdout.includes('NODE:'));
    assert.match(result.stderr, avds.length ? /多个 AVD/ : /没有已安装的 AVD/);
  }
});

test('explicit AVD selection overrides local configuration', windowsOnly, () => {
  const result = run('emu', { config: { EmulatorName: 'other_avd' }, args: ['-EmulatorName', 'test_avd'] });
  success(result);
  assert.match(result.stdout, /--launch\|test_avd/);
});

test('MuMu reads local paths and uses the configured instance and exact ADB serial', windowsOnly, () => {
  const result = run('mumu', {
    config: { MuMuIndex: 1, MuMuAdbAddr: '127.0.0.1:5557' },
    env: { KIRA_TEST_SERIAL: '127.0.0.1:5557' },
  });
  success(result);
  assert.match(result.stdout, /MUMU:control\|-v\|1\|launch/);
  assert.match(result.stdout, /DEVICE:127\.0\.0\.1:5557/);
  assert.match(result.stdout, /TARGET:mumu/);
});

test('command-line MuMu configuration takes precedence over environment and local configuration', windowsOnly, () => {
  const result = run('mumu', {
    config: { MuMuIndex: 1 },
    args: ['-MuMuIndex', '3', '-MuMuAdbAddr', '127.0.0.1:6000'],
    env: { KIRA_MUMU_INDEX: '2', KIRA_TEST_SERIAL: '127.0.0.1:6000' },
  });
  success(result);
  assert.match(result.stdout, /MUMU:control\|-v\|3\|launch/);
  assert.match(result.stdout, /DEVICE:127\.0\.0\.1:6000/);
});

test('environment overrides local MuMu configuration', windowsOnly, () => {
  const result = run('mumu', {
    config: { MuMuIndex: 1 },
    env: { KIRA_MUMU_INDEX: '2', KIRA_MUMU_ADB_ADDR: '127.0.0.1:6001', KIRA_TEST_SERIAL: '127.0.0.1:6001' },
  });
  success(result);
  assert.match(result.stdout, /MUMU:control\|-v\|2\|launch/);
  assert.match(result.stdout, /DEVICE:127\.0\.0\.1:6001/);
});

test('help, log and stop remain available even with malformed device configuration', windowsOnly, () => {
  for (const args of [[], ['-Log'], ['-Stop']]) success(run('', { config: '{invalid json', args }));
});

function backendCalls(result) {
  return [...result.stdout.matchAll(/^BACKEND:([^\r\n]+)/gm)].map(match => match[1]);
}

function assertNoOperations(result) {
  assert.doesNotMatch(result.stdout, /(?:BACKEND|NODE|FLUTTER|MUMU):/);
}

for (const [name, options, backend] of [
  ['default', {}, 'auto'],
  ['local configuration', { config: { Backend: 'tui' } }, 'tui'],
  ['environment over local configuration', { config: { Backend: 'tui' }, env: { KIRA_HERDR_BACKEND: 'app' } }, 'app'],
  ['blank environment falls back to local configuration', { config: { Backend: 'app' }, env: { KIRA_HERDR_BACKEND: ' ' } }, 'app'],
  ...['auto', 'tui', 'app'].map(backend => [
    `explicit ${backend} over environment and local configuration`,
    { config: { Backend: 'invalid-local' }, env: { KIRA_HERDR_BACKEND: 'invalid-env' }, args: ['-Backend', backend] },
    backend,
  ]),
  ['case normalization', { args: ['-Backend', 'TUI'] }, 'tui'],
]) {
  test(`backend selection: ${name} applies before has, stop and start`, windowsOnly, () => {
    const result = run('win', { ...options, alive: true });
    success(result);
    assert.deepEqual(backendCalls(result), [`has|${backend}`, `stop|${backend}`, `start|${backend}`]);
  });
}

for (const operation of ['Log', 'Stop']) {
  for (const [name, options, backend] of [
    ['ignores local backend and malformed device fields', { config: { Backend: 'tui', MuMuIndex: 'invalid' } }, 'auto'],
    ['uses environment without parsing local JSON', { config: '{invalid json', env: { KIRA_HERDR_BACKEND: 'tui' } }, 'tui'],
    ['explicit option overrides environment without parsing local JSON', { config: '{invalid json', env: { KIRA_HERDR_BACKEND: 'invalid' }, args: ['-Backend', 'app'] }, 'app'],
  ]) {
    test(`-${operation} ${name}`, windowsOnly, () => {
      // Even when a target is supplied, these operations must not prepare devices or load their configuration.
      const result = run('emu', { ...options, args: [`-${operation}`, ...(options.args || [])] });
      success(result);
      assert.deepEqual(backendCalls(result), [`${operation.toLowerCase()}|${backend}`]);
      assert.doesNotMatch(result.stdout, /(?:FLUTTER|MUMU):/);
    });
  }
  test(`-${operation} rejects an unknown environment backend before calling the driver`, windowsOnly, () => {
    const result = run('', { config: '{invalid json', args: [`-${operation}`], env: { KIRA_HERDR_BACKEND: 'invalid' } });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /未知 Herdr 后端/);
    assertNoOperations(result);
  });
}

for (const target of ['mumu', 'emu']) {
  for (const [source, options, error] of [
    ['command line', { args: ['-Backend', 'invalid'] }, /Backend/],
    ['environment', { env: { KIRA_HERDR_BACKEND: 'invalid' } }, /未知 Herdr 后端/],
    ['local JSON', { config: { Backend: 'invalid' } }, /未知 Herdr 后端/],
  ]) {
    test(`${target} rejects unknown ${source} backend before device preparation or stopping the old app`, windowsOnly, () => {
      const result = run(target, { ...options, alive: true });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, error);
      assertNoOperations(result);
    });
  }
}

test('help describes both Herdr backends and config-free control operations', windowsOnly, () => {
  const result = run('', { config: '{invalid json', env: { KIRA_HERDR_BACKEND: 'invalid' } });
  success(result);
  assert.match(result.stdout, /-Backend auto\|tui\|app/);
  assert.match(result.stdout, /Herdr TUI（herdr）/);
  assert.match(result.stdout, /Herdr app（hc \+ herdr-app）/);
  assert.match(result.stdout, /-Backend > KIRA_HERDR_BACKEND > JSON 字段 Backend > auto/);
  assert.match(result.stdout, /-Stop 与 -Log 不读取本机配置/);
  assertNoOperations(result);
});
