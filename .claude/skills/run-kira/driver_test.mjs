import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { createDriver } from './driver.mjs';

const ROOT = process.cwd();
const READY = 'Flutter run key commands.\nr Hot reload.\nR Hot restart.';
const result = data => ({ status: 0, stdout: JSON.stringify(data), stderr: '' });

function fixture(options = {}) {
  const calls = [];
  const messages = [];
  const appCalls = [];
  const state = {
    terminal: { address: 't7', cwd: ROOT, state: 'live', argv: ['cmd.exe', '/c', 'flutter run -d windows'] },
    text: READY,
    ...options,
  };
  const driver = createDriver({
    root: ROOT,
    windows: true,
    env: { KIRA_HERDR_BACKEND: "app", ...options.env },
    output: { log: text => messages.push(text), error: text => messages.push(text) },
    invokeApp: args => {
      appCalls.push(args);
      if (options.invokeApp) return options.invokeApp(args, state, appCalls);
      if (options.appResult) return options.appResult;
      if (args[0] === 'do') {
        state.tabName = args[args.indexOf('--name') + 1];
        return result({});
      }
      const spaces = [...(options.spaces || [{ id: 'sp-existing', name: 'kira', machine: null }])];
      if (state.created) {
        let space = spaces.find(space => space.id === state.spaceId);
        if (!space) { space = { id: state.spaceId, name: 'kira', machine: null }; spaces.push(space); }
        space = { ...space, tabs: [...(space.tabs || []), { id: 'tb-run', name: state.tabName || '1', terminals: [{ terminal: state.terminal.address }] }] };
        spaces[spaces.findIndex(item => item.id === space.id)] = space;
      }
      return result({ spaces });
    },
    invoke: args => {
      calls.push(args);
      if (options.invoke) return options.invoke(args, state);
      switch (args[0]) {
        case 'ls': return result({ terminals: state.entries || (state.terminal ? [state.terminal] : []) });
        case 'get': return result(state.terminal);
        case 'label':
          state.terminal.labels = { ...state.terminal.labels, 'kira.ready': 'true' };
          return result({ labels: state.terminal.labels });
        case 'read': return result({ text: state.text, complete: true });
        case 'run':
          state.created = true;
          state.spaceId = args.find(arg => arg.startsWith('herdr.space=')).slice('herdr.space='.length);
          state.terminal = { address: 't8', cwd: ROOT, state: 'live', argv: args.slice(args.indexOf('--') + 1) };
          return result(state.terminal);
        case 'keys':
          options.onKeys?.(args, state);
          return result({ status: null, turn: 0 });
        case 'wait':
          options.onWait?.(args, state);
          return result({ reason: 'timeout', ended: false });
        case 'kill':
          state.terminal.state = 'finished';
          return result(state.terminal);
        case 'rm': return result({ removed: args[1] });
        default: throw new Error(`Unexpected hc command: ${args.join(' ')}`);
      }
    },
  });
  return { execute: args => driver.execute(args), calls, appCalls, messages, state };
}

const commands = f => f.calls.map(args => args[0]);

test('has performs one lookup and distinguishes live, missing, and recovered shell', async () => {
  const live = fixture();
  assert.equal(await live.execute(['has']), 0);
  assert.deepEqual(commands(live), ['ls', 'get']);
  assert.deepEqual(live.messages, ['ALIVE']);
  const missing = fixture({ terminal: null });
  assert.equal(await missing.execute(['has']), 1);
  assert.deepEqual(missing.messages, ['DEAD']);
  const shell = fixture({ terminal: { address: 't7', cwd: ROOT, state: 'live', argv: ['pwsh.exe'] } });
  assert.equal(await shell.execute(['has']), 1);
  assert.equal(await shell.execute(['reload', '--yes']), 1);
  assert.ok(!commands(shell).includes('keys'));
});

test('hc failure is not reported as DEAD', async () => {
  const f = fixture({ invoke: () => ({ status: 1, stderr: 'core unavailable', stdout: '' }) });
  assert.equal(await f.execute(['has']), 2);
  assert.deepEqual(f.messages, ['core unavailable']);
});

test('foreign cwd, remote terminals and ambiguous targets are not controlled', async () => {
  for (const entry of [
    { address: 't9', cwd: path.join(ROOT, 'other'), state: 'live' },
    { address: 'remote/t9', cwd: ROOT, state: 'live' },
  ]) {
    const f = fixture({ entries: [entry] });
    assert.equal(await f.execute(['has']), 1);
    assert.ok(!commands(f).includes('get'));
  }
  const f = fixture({ entries: ['t7', 't8'].map(address => ({ address, cwd: ROOT, state: 'live' })) });
  assert.equal(await f.execute(['stop', '--yes']), 2);
  assert.ok(!commands(f).includes('kill'));
});

test('start uses hc, explicit cwd, ownership/UI labels and persistent lifetime', async () => {
  const f = fixture({ terminal: null, env: { KIRA_DEVICE: '127', COPY_AUTH_KEY: 'test_key' } });
  assert.equal(await f.execute(['start', '--no-wait']), 0);
  const run = f.calls.find(args => args[0] === 'run');
  for (const flag of ['--bg', '--outlive-parent', '--no-notify']) assert.ok(run.includes(flag));
  assert.equal(run[run.indexOf('--cwd') + 1], ROOT);
  assert.ok(run.includes('kira.role=run'));
  assert.ok(run.includes('herdr.space=sp-existing'));
  assert.ok(!run.some(arg => arg.startsWith('herdr.tab=')));
  assert.deepEqual(f.appCalls, [['ls'], ['ls'], ['do', 'tab.rename', '--id', 'tb-run', '--name', 'run-mumu']]);
  assert.deepEqual(run.slice(run.indexOf('--') + 1), [
    'cmd.exe', '/d', '/s', '/c', 'flutter run -d 127 --dart-define=COPY_AUTH_KEY=test_key',
  ]);
  assert.ok(!f.messages.join('\n').includes('test_key'));
});

test('start returns asynchronously by default without reading or waiting for Flutter', async () => {
  const f = fixture({ terminal: null, text: 'Building...' });
  assert.equal(await f.execute(['start']), 0);
  assert.deepEqual(commands(f), ['ls', 'run']);
  assert.match(f.messages.join('\n'), /已后台启动/);
  assert.ok(!f.messages.join('\n').includes('Flutter 就绪'));
});

test('new tabs are named for their devices without waiting for Flutter', async () => {
  for (const [device, name] of [['windows', 'run-win'], ['127', 'run-mumu'], ['emu', 'run-emu'], ['custom', 'run-custom']]) {
    const f = fixture({ terminal: null, env: { KIRA_DEVICE: device } });
    assert.equal(await f.execute(['start']), 0);
    assert.equal(f.state.tabName, name);
    assert.deepEqual(commands(f), ['ls', 'run']);
    assert.deepEqual(f.appCalls.at(-1), ['do', 'tab.rename', '--id', 'tb-run', '--name', name]);
  }
});

test('precise Android serials retain the requested target tab name', async () => {
  for (const [target, device, name] of [['mumu', '127.0.0.1:5557', 'run-mumu'], ['emu', 'emulator-5678', 'run-emu']]) {
    const f = fixture({ terminal: null, env: { KIRA_TARGET: target, KIRA_DEVICE: device } });
    assert.equal(await f.execute(['start']), 0);
    assert.equal(f.state.tabName, name);
  }
});

test('naming waits only for tab adoption and targets the terminal rather than the focused tab', async () => {
  let renamed;
  const f = fixture({ terminal: null, invokeApp: (args, state, calls) => {
    if (args[0] === 'do') { renamed = args; return result({}); }
    return result({ spaces: [{ id: 'sp-existing', name: 'kira', machine: null, tabs: [
      { id: 'tb-focused', terminals: [{ terminal: 't-other' }] },
      ...(state.created && calls.length >= 3 ? [{ id: 'tb-target', terminals: [{ terminal: state.terminal.address }] }] : []),
    ] }] });
  } });
  assert.equal(await f.execute(['start']), 0);
  assert.deepEqual(renamed, ['do', 'tab.rename', '--id', 'tb-target', '--name', 'run-win']);
  assert.deepEqual(commands(f), ['ls', 'run']);
});

test('tab adoption or rename failure is bounded and does not restart an already launched process', async () => {
  const missing = fixture({ terminal: null, invokeApp: () => result({ spaces: [{ id: 'sp-existing', name: 'kira', machine: null }] }) });
  assert.equal(await missing.execute(['start']), 2);
  assert.equal(missing.appCalls.length, 9);
  assert.equal(commands(missing).filter(cmd => cmd === 'run').length, 1);
  assert.match(missing.messages.at(-1), /已后台启动.*未能命名/);
  const failed = fixture({ terminal: null, invokeApp: (args, state) => args[0] === 'do'
    ? { status: 1, stdout: '', stderr: 'tab rename rejected' }
    : result({ spaces: [{ id: 'sp-existing', name: 'kira', machine: null, tabs: state.created
      ? [{ id: 'tb-run', terminals: [{ terminal: state.terminal.address }] }] : [] }] }) });
  assert.equal(await failed.execute(['start']), 2);
  assert.equal(failed.messages.at(-1), 'tab rename rejected');
  assert.equal(commands(failed).filter(cmd => cmd === 'run').length, 1);
});

test('reusing a live terminal is also asynchronous and does not create another tab', async () => {
  const f = fixture({ text: 'Building...' });
  assert.equal(await f.execute(['start']), 0);
  assert.deepEqual(commands(f), ['ls', 'get']);
  assert.deepEqual(f.appCalls, []);
});

test('existing workspace is selected by name, not ID or its launch folder', async () => {
  const f = fixture({ terminal: null, spaces: [
    { id: 'remote/kira', name: 'kira', machine: 'remote', active: true },
    { id: 'sp-existing', name: 'kira', machine: null, folder: path.join(ROOT, 'other') },
  ] });
  assert.equal(await f.execute(['start']), 0);
  assert.ok(f.calls.find(args => args[0] === 'run').includes('herdr.space=sp-existing'));
});

test('duplicate names prefer the active workspace, then the original rather than the legacy fixed ID', async () => {
  for (const active of [true, false]) {
    const f = fixture({ terminal: null, spaces: [
      { id: 'kira', name: 'kira', machine: null },
      { id: 'sp-original', name: 'kira', machine: null, active },
    ] });
    assert.equal(await f.execute(['start']), 0);
    assert.ok(f.calls.find(args => args[0] === 'run').includes('herdr.space=sp-original'));
  }
});

test('a new workspace is requested only when no local kira workspace exists', async () => {
  const f = fixture({ terminal: null, spaces: [{ id: 'remote/kira', name: 'kira', machine: 'remote' }] });
  assert.equal(await f.execute(['start']), 0);
  assert.ok(f.calls.find(args => args[0] === 'run').includes('herdr.space=kira'));
});

test('workspace lookup failure does not silently create a duplicate workspace', async () => {
  const f = fixture({ terminal: null, appResult: { status: 1, stdout: '', stderr: 'Herdr not running' } });
  assert.equal(await f.execute(['start']), 2);
  assert.ok(!commands(f).includes('run'));
  assert.equal(f.messages.at(-1), 'Herdr not running');
});

test('conflicting wait options fail before changing terminals', async () => {
  const f = fixture();
  assert.equal(await f.execute(['start', '--wait', '--no-wait']), 2);
  assert.deepEqual(f.calls, []);
});

test('start rejects shell metacharacters before launching', async () => {
  for (const env of [{ KIRA_DEVICE: 'windows & calc' }, { COPY_AUTH_KEY: 'key & calc' }]) {
    const f = fixture({ terminal: null, env });
    assert.equal(await f.execute(['start']), 2);
    assert.ok(!commands(f).includes('run'));
  }
});

test('start --wait explicitly waits for readiness and reuses an existing build', async () => {
  const f = fixture({ text: 'Building Windows application...', onWait: (_, s) => { s.text = READY; } });
  assert.equal(await f.execute(['start', '--wait']), 0);
  assert.ok(commands(f).includes('wait'));
  assert.ok(!commands(f).includes('run'));
  assert.match(f.messages.join('\n'), /Flutter 就绪/);
});

test('startup timeout or exit does not claim success or launch a duplicate', async () => {
  for (const onWait of [undefined, (_, s) => { s.terminal.state = 'finished'; s.text = 'Error: build failed'; }]) {
    const f = fixture({ text: 'Building...', onWait });
    assert.equal(await f.execute(['start', '--wait']), 1);
    assert.ok(!commands(f).includes('run'));
    assert.ok(!commands(f).includes('kill'));
    assert.ok(!f.messages.join('\n').includes('✓'));
  }
});

test('mutating commands remain dry runs without --yes', async () => {
  for (const cmd of ['reload', 'restart', 'quit', 'stop']) {
    const f = fixture();
    assert.equal(await f.execute([cmd]), 0);
    assert.ok(!commands(f).some(cmd => ['keys', 'kill', 'rm'].includes(cmd)));
  }
});

test('reload checks new output, ignoring old exceptions', async () => {
  const f = fixture({
    text: 'Unhandled Exception: historical error\n' + READY,
    onKeys: (_, s) => { s.text += '\nReloaded 1 of 100 libraries in 50ms.'; },
  });
  assert.equal(await f.execute(['reload', '--yes']), 0);
  assert.deepEqual(f.calls.find(args => args[0] === 'keys'), ['keys', '--json', 't7', 'r']);
  assert.ok(!commands(f).includes('wait'));
});

test('Windows accessibility tree noise does not fail a successful reload', async () => {
  const f = fixture({
    onKeys: (_, s) => {
      s.text += '\n[ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)] ' +
        'Failed to update ui::AXTree, error: 157 will not be in the tree and is not the new root' +
        '\nProblem getting monitor brightness' +
        '\nReloaded 100 of 3395 libraries in 2172ms.';
    },
  });
  assert.equal(await f.execute(['reload', '--yes']), 0);
  assert.ok(!commands(f).includes('wait'));
});

test('an earlier failed attempt in the same output window does not mask success', async () => {
  const f = fixture({
    onKeys: (_, s) => {
      s.text += '\nlib/a.dart: Error: stale failure from the previous attempt' +
        '\nPerforming hot reload...' +
        '\nReloaded 2 of 100 libraries in 40ms.';
    },
  });
  assert.equal(await f.execute(['reload', '--yes']), 0);
  assert.ok(!commands(f).includes('wait'));
});

test('restart sends shift+r because hc keys R lowercases the character', async () => {
  const f = fixture({ onWait: (_, s) => { s.text += '\nRestarted application in 300ms.'; } });
  assert.equal(await f.execute(['restart', '--yes']), 0);
  assert.deepEqual(f.calls.find(args => args[0] === 'keys'), ['keys', '--json', 't7', 'shift+r']);
});

test('a stale Reloaded marker cannot prove the current operation succeeded', async () => {
  const f = fixture({ text: READY + '\nReloaded 1 library in 100ms.' });
  assert.equal(await f.execute(['reload', '--yes']), 1);
  assert.ok(commands(f).includes('wait'));
  assert.ok(!f.messages.join('\n').includes('✓'));
});

test('readiness persists when startup output has scrolled away', async () => {
  const f = fixture({ onKeys: (_, s) => { s.text += '\nReloaded 1 library in 20ms.'; } });
  assert.equal(await f.execute(['log', '10']), 0);
  f.state.text = 'Recent application log without startup markers';
  assert.equal(await f.execute(['reload', '--yes']), 0);
});

test('spinner redraw cannot reuse a historical completion marker', async () => {
  const f = fixture({
    text: READY + '\nReloaded 1 library in 100ms.\nPerforming hot reload...a',
    onKeys: (_, s) => { s.text = s.text.replace('...a', '...b'); },
  });
  assert.equal(await f.execute(['reload', '--yes']), 1);
  assert.ok(!f.messages.join('\n').includes('✓'));
});

test('an unready Flutter process receives no reload key', async () => {
  const f = fixture({ text: 'Building...' });
  assert.equal(await f.execute(['reload', '--yes']), 1);
  assert.ok(!commands(f).includes('keys'));
});

test('key delivery errors and reload rejection propagate actual failures', async () => {
  const f = fixture({ onKeys: () => { throw new Error('terminal unavailable'); } });
  assert.equal(await f.execute(['reload', '--yes']), 2);
  assert.equal(f.messages.at(-1), 'terminal unavailable');
  const rejected = fixture({ onKeys: (_, s) => { s.text += '\nHot reload was rejected: field type changed'; } });
  assert.equal(await rejected.execute(['reload', '--yes']), 2);
  assert.ok(!commands(rejected).includes('wait'));
});

test('quit preserves finished logs, while stop removes only its selected terminal', async () => {
  const f = fixture({ onKeys: (_, s) => { s.terminal.state = 'finished'; s.text += '\nApplication finished.'; } });
  assert.equal(await f.execute(['quit', '--yes']), 0);
  assert.ok(!commands(f).includes('rm'));
  assert.equal(await f.execute(['log', '10']), 0);
  assert.equal(await f.execute(['stop', '--yes']), 0);
  assert.deepEqual(f.calls.find(args => args[0] === 'rm'), ['rm', '--json', 't7']);
  assert.ok(!commands(f).includes('kill'));
  const live = fixture();
  assert.equal(await live.execute(['stop', '--yes']), 0);
  assert.deepEqual(live.calls.find(args => args[0] === 'kill'), ['kill', '--json', 't7']);
});

test('finished status shows logs and exit reason; send preserves uppercase and enter', async () => {
  const finished = fixture({ terminal: { address: 't7', cwd: ROOT, state: 'finished', exit_code: 1, reason: 'exited' }, text: 'Error: failed' });
  assert.equal(await finished.execute(['status']), 1);
  assert.match(finished.messages.join('\n'), /退出码: 1/);
  assert.match(finished.messages.join('\n'), /Error: failed/);
  const f = fixture();
  assert.equal(await f.execute(['send', 'R', '--enter']), 0);
  assert.deepEqual(f.calls.find(args => args[0] === 'keys'), ['keys', '--json', 't7', 'shift+r', 'enter']);
});

test('invalid log lengths are rejected and secret values are redacted from errors', async () => {
  for (const n of ['0', '-1', 'NaN', '1.5']) assert.equal(await fixture().execute(['log', n]), 2);
  const f = fixture({ env: { COPY_AUTH_KEY: 'test_key' }, invoke: () => { throw new Error('failed test_key'); } });
  assert.equal(await f.execute(['has']), 2);
  assert.deepEqual(f.messages, ['failed [REDACTED]']);
});

test('real hc integration uses an isolated core and a fake Flutter process', { skip: process.env.KIRA_TEST_HC !== '1' }, async () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'kira-hc-test-'));
  const env = {
    ...process.env,
    HC_SESSION: `kira-test-${process.pid}`,
    XDG_CONFIG_HOME: dir,
    XDG_DATA_HOME: dir,
    XDG_STATE_HOME: dir,
    APPDATA: dir,
    LOCALAPPDATA: dir,
  };
  const script = path.join(dir, 'flutter');
  writeFileSync(script, `
process.stdin.setRawMode(true);
process.stdin.on('data', data => {
  for (const key of data.toString()) {
    if (key === 'r') console.log('Reloaded 1 library in 20ms.');
    if (key === 'R') console.log('Restarted application in 30ms.');
    if (key === 'q') { console.log('Application finished.'); process.exit(0); }
  }
});
console.log('Flutter run key commands.');
`);
  const calls = [];
  const messages = [];
  let address;
  const invoke = args => {
    calls.push(args);
    if (args[0] === 'run') args = [...args.slice(0, args.indexOf('--') + 1), process.execPath, script];
    const response = spawnSync('hc', args, { env, encoding: 'utf8', windowsHide: true });
    if (args[0] === 'run' && response.status === 0) address = JSON.parse(response.stdout).address;
    return response;
  };
  const driver = createDriver({
    invoke,
    invokeApp: args => args[0] === 'do' ? result({}) : result({ spaces: [{ id: 'sp-integration', name: 'kira', machine: null,
      tabs: address ? [{ id: 'tb-integration', terminals: [{ terminal: address }] }] : [],
    }] }),
    root: ROOT,
    env: { KIRA_HERDR_BACKEND: "app" },
    output: { log: t => messages.push(t), error: t => messages.push(t) },
  });
  const execute = async args => {
    const code = await driver.execute(args);
    assert.equal(code, 0, messages.join('\n'));
  };
  try {
    await execute(['start']);
    assert.ok(!calls.some(args => args[0] === 'wait'));
    await execute(['start', '--wait']);
    assert.equal(calls.filter(args => args[0] === 'run').length, 1);
    await execute(['has']);
    await execute(['reload', '--yes']);
    await execute(['restart', '--yes']);
    await execute(['quit', '--yes']);
    await execute(['log', '20']);
    await execute(['stop', '--yes']);
    assert.ok(messages.some(t => t.includes('热重启 (R)完成')));
    assert.ok(calls.every(args => args[0] !== 'server'));
  } finally {
    // 仅清理本测试的 core；HC_SESSION 与所有存储目录均与用户会话隔离。
    spawnSync('hc', ['server', 'stop'], { env, encoding: 'utf8' });
    rmSync(dir, { recursive: true, force: true });
  }
});
