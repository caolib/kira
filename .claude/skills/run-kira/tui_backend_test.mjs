import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import test from 'node:test';
import { createDriver } from './driver.mjs';
import { readWindowsProcessTable } from './tui_backend.mjs';

const root = process.cwd();
const owner = createHash('sha256').update(root.replaceAll('\\', '/').toLowerCase()).digest('hex');
const ok = result => ({ status: 0, stdout: JSON.stringify({ result }), stderr: '' });
const fail = (code, message) => ({ status: 1, stdout: '', stderr: JSON.stringify({ error: { code, message } }) });
const ready = 'Flutter run key commands.';

function fixture(options = {}) {
  const calls = [];
  const appCalls = [];
  const hcCalls = [];
  const messages = [];
  let processReads = 0;
  const state = {
    pane: null, text: '', running: false, processes: [],
    spaces: [{ workspace_id: 'w1', label: 'kira', focused: true }],
    ...options,
  };
  const invokeHerdr = args => {
    calls.push(args);
    if (options.invokeHerdr) return options.invokeHerdr(args, state);
    const [group, cmd, id] = args;
    if (group === 'workspace' && cmd === 'list') return ok({ workspaces: state.spaces });
    if ((group === 'workspace' || group === 'tab') && cmd === 'create') {
      state.pane = { pane_id: 'w1:p2', terminal_id: 'term-test', workspace_id: 'w1', tab_id: 'w1:t2', cwd: root, tokens: {} };
      return ok({ workspace: { workspace_id: 'w1' }, tab: { tab_id: 'w1:t2' }, root_pane: state.pane });
    }
    if (group === 'tab' && cmd === 'rename') return ok({});
    if (group === 'pane') switch (cmd) {
      case 'list': return ok({ panes: state.pane ? [state.pane] : [] });
      case 'get': return state.pane ? ok({ pane: state.pane }) : fail('pane_not_found', 'not found');
      case 'read': return { status: 0, stdout: args.at(-1) === '5000' && state.history ? state.history : state.text, stderr: '' };
      case 'process-info': return ok({ process_info: { shell_pid: 1, foreground_processes: state.running ? [{ name: 'dart.exe', pid: 2 }] : [{ name: 'pwsh.exe', pid: 1 }] } });
      case 'report-metadata':
        for (let i = 0; i < args.length; i++) if (args[i] === '--token') {
          const value = args[++i];
          const split = value.indexOf('=');
          state.pane.tokens[value.slice(0, split)] = value.slice(split + 1);
        }
        return ok({});
      case 'run': state.running = true; state.text = options.noReady ? 'Building...' : ready; return { status: 0, stdout: '', stderr: '' };
      case 'send-text':
        if (args[3] === 'r') state.text += '\nReloaded 1 library in 20ms.';
        if (args[3] === 'R') state.text += '\nRestarted application in 30ms.';
        if (args[3] === 'q') { state.running = false; state.text += `\nKIRA_${state.pane.tokens.kira_run}_EXIT_0`; }
        return ok({});
      case 'send-keys': return ok({});
      case 'close': state.pane = null; return ok({});
    }
    throw new Error(`unexpected ${args.join(' ')}`);
  };
  const driver = createDriver({
    root, windows: true,
    env: { KIRA_HERDR_BACKEND: 'tui', ...options.env },
    invokeHerdr,
    readProcessTable: () => {
      processReads++;
      if (options.processError) throw options.processError;
      return state.processes;
    },
    invoke: args => { hcCalls.push(args); return options.hcResult || { status: 1, stdout: '', stderr: 'hc not installed' }; },
    invokeApp: args => { appCalls.push(args); return options.appResult || { status: 1, stdout: '', stderr: 'no Herdr window: 10061' }; },
    output: { log: value => messages.push(value), error: value => messages.push(value) },
  });
  return { state, calls, appCalls, hcCalls, messages, get processReads() { return processReads; }, execute: args => driver.execute(args) };
}

function ownedPane() {
  return {
    pane_id: 'w1:p2', terminal_id: 'term-test', cwd: root,
    tokens: { kira_project: owner, kira_role: 'run', kira_terminal: 'term-test', kira_run: 'test', kira_started: String(Date.now() - 60000), kira_device: 'windows' },
  };
}

test('TUI runs without hc or herdr-app, reuses workspace, names tab and preserves focus', async () => {
  const f = fixture({ env: { KIRA_TARGET: 'mumu', KIRA_DEVICE: '127.0.0.1:5557' } });
  assert.equal(await f.execute(['start']), 0, f.messages.join('\n'));
  const create = f.calls.find(args => args[1] === 'create');
  assert.deepEqual(create, ['tab', 'create', '--workspace', 'w1', '--cwd', root, '--label', 'run-mumu', '--no-focus']);
  assert.ok(!f.calls.some(args => args[1] === 'wait-output'));
  assert.equal(f.appCalls.length, 0);
  assert.equal(f.hcCalls.length, 0);
  assert.equal(await f.execute(['has']), 0);
  assert.equal(await f.execute(['reload', '--yes']), 0);
  assert.equal(await f.execute(['restart', '--yes']), 0);
  assert.ok(f.calls.some(args => args[1] === 'send-text' && args[3] === 'R'));
  assert.equal(await f.execute(['quit', '--yes']), 0);
  assert.equal(await f.execute(['has']), 1);
  assert.equal(await f.execute(['log', '30']), 0);
  assert.equal(await f.execute(['stop', '--yes']), 0);
  assert.equal(f.state.pane, null);
});

test('TUI creates only the first tab when no kira workspace exists', async () => {
  const f = fixture({ spaces: [] });
  assert.equal(await f.execute(['start']), 0);
  assert.equal(f.calls.filter(args => args[1] === 'create').length, 1);
  assert.ok(f.calls.some(args => args[0] === 'workspace' && args[1] === 'create'));
  assert.ok(f.calls.some(args => args[0] === 'tab' && args[1] === 'rename' && args[3] === 'run-win'));
});

test('TUI prefers the calling kira workspace over another focused workspace', async () => {
  const f = fixture({ env: { HERDR_WORKSPACE_ID: 'w2' }, spaces: [
    { workspace_id: 'w1', label: 'kira', focused: true }, { workspace_id: 'w2', label: 'kira' },
  ] });
  assert.equal(await f.execute(['start']), 0);
  assert.equal(f.calls.find(args => args[1] === 'create')[3], 'w2');
});

test('automatic selection prefers the TUI caller even if the app is open', async () => {
  const f = fixture({ env: { KIRA_HERDR_BACKEND: 'auto', HERDR_ENV: '1', HERDR_PANE_ID: 'w1:p1' } });
  assert.equal(await f.execute(['has']), 1);
  assert.equal(f.appCalls.length, 0);
  assert.equal(f.hcCalls.length, 0);
});

test('automatic selection falls back to TUI when app window is unavailable', async () => {
  const f = fixture({ env: { KIRA_HERDR_BACKEND: 'auto' } });
  assert.equal(await f.execute(['start']), 0, f.messages.join('\n'));
  assert.deepEqual(f.appCalls, [['ls']]);
  assert.equal(f.hcCalls.length, 0);
});

test('explicit app backend overrides TUI context and does not silently switch', async () => {
  const f = fixture({ env: { HERDR_ENV: '1', HERDR_PANE_ID: 'w1:p1' } });
  assert.equal(await f.execute(['has', '--backend', 'app']), 2);
  assert.equal(f.calls.length, 0);
  assert.equal(f.hcCalls.length, 1);
});

test('invalid or missing backend option fails before any control command', async () => {
  for (const args of [['has', '--backend'], ['start', '--backend', 'other']]) {
    const f = fixture();
    assert.equal(await f.execute(args), 2);
    assert.equal(f.calls.length + f.hcCalls.length + f.appCalls.length, 0);
  }
});

test('unrelated, recovered and exited shell panes do not receive keys', async () => {
  for (const pane of [
    { ...ownedPane(), tokens: { kira_project: 'other', kira_role: 'run' } },
    { ...ownedPane(), terminal_id: 'recovered-terminal' },
    ownedPane(),
  ]) {
    const f = fixture({ pane, text: ready, running: false });
    assert.equal(await f.execute(['reload', '--yes']), 1);
    assert.ok(!f.calls.some(args => args[1] === 'send-text' || args[1] === 'send-keys'));
  }
});

test('Windows shell-only foreground info falls back to the owned descendant tree', async () => {
  const processes = [
    { pid: 1, parentPid: 0, name: 'pwsh.exe' },
    { pid: 2, parentPid: 1, name: 'powershell.exe' },
    { pid: 3, parentPid: 2, name: 'cmd.exe' },
    { pid: 4, parentPid: 3, name: 'dart.exe' },
    { pid: 5, parentPid: 4, name: 'dartvm.exe' },
    { pid: 6, parentPid: 5, name: 'kira.exe' },
  ];
  const f = fixture({ pane: ownedPane(), text: ready, processes });
  assert.equal(await f.execute(['has']), 0, f.messages.join('\n'));
  assert.ok(f.processReads > 0);
  assert.equal(await f.execute(['start']), 0);
  assert.ok(!f.calls.some(args => args[1] === 'create' || args[1] === 'run'));
  assert.equal(await f.execute(['reload', '--yes']), 0, f.messages.join('\n'));
  assert.ok(f.messages.includes('✓ 热重载 (r)完成。'));

  // 已就绪标签和旧日志不能让退出后的 shell 继续被视为 Flutter。
  f.state.processes = processes.slice(0, 3);
  assert.equal(await f.execute(['has']), 1);
  const sent = f.calls.filter(args => args[1] === 'send-text').length;
  assert.equal(await f.execute(['reload', '--yes']), 1);
  assert.equal(f.calls.filter(args => args[1] === 'send-text').length, sent);
});

test('first reload recovers readiness from history when startup logs have scrolled away', async () => {
  const f = fixture({ pane: ownedPane(), text: 'recent output', history: `${ready}\nolder output`, running: true });
  assert.equal(await f.execute(['reload', '--yes']), 0, f.messages.join('\n'));
  assert.equal(f.state.pane.tokens.kira_ready, 'true');
  const historyReads = () => f.calls.filter(args => args[1] === 'read' && args.at(-1) === '5000').length;
  assert.equal(historyReads(), 1);
  f.state.history = '';
  f.state.text = 'more recent output';
  assert.equal(await f.execute(['reload', '--yes']), 0);
  assert.equal(historyReads(), 1);
});

test('unrelated runtimes and shell wrappers do not count as a live Flutter descendant', async () => {
  const f = fixture({ pane: ownedPane(), text: ready, processes: [
    { pid: 1, parentPid: 0, name: 'pwsh.exe' },
    { pid: 2, parentPid: 1, name: 'powershell.exe' },
    { pid: 3, parentPid: 2, name: 'cmd.exe' },
    { pid: 4, parentPid: 100, name: 'dart.exe' },
    { pid: 5, parentPid: 4, name: 'kira.exe' },
  ] });
  assert.equal(await f.execute(['has']), 1);
  assert.equal(await f.execute(['reload', '--yes']), 1);
  assert.ok(!f.calls.some(args => args[1] === 'send-text'));
});

test('recovered terminals and explicit exit markers override live descendants', async () => {
  for (const options of [
    { pane: { ...ownedPane(), terminal_id: 'recovered' }, text: ready },
    { pane: ownedPane(), text: `${ready}\nKIRA_test_EXIT_0` },
  ]) {
    const f = fixture({ ...options, processes: [{ pid: 2, parentPid: 1, name: 'dartvm.exe' }] });
    assert.equal(await f.execute(['has']), 1);
    assert.equal(f.processReads, 0);
    assert.equal(await f.execute(['reload', '--yes']), 1);
    assert.ok(!f.calls.some(args => args[1] === 'send-text'));
  }
});

test('process query errors remain errors rather than DEAD or triggering a new launch', async () => {
  const f = fixture({ pane: ownedPane(), processError: new Error('CIM access denied') });
  for (const command of ['has', 'start', 'reload']) {
    assert.equal(await f.execute([command, '--yes']), 2);
    assert.equal(f.messages.at(-1), 'CIM access denied');
  }
  assert.ok(!f.messages.includes('DEAD'));
  assert.ok(!f.calls.some(args => ['create', 'run', 'send-text', 'close'].includes(args[1])));
});

test('Windows process table reads only process identity and validates results', () => {
  const table = readWindowsProcessTable((command, args, options) => {
    assert.equal(command, 'powershell.exe');
    assert.ok(args.includes('-NoProfile'));
    assert.ok(options.timeout > 0);
    assert.ok(!args.at(-1).includes('CommandLine'));
    return { status: 0, stdout: JSON.stringify([{ ProcessId: 2, ParentProcessId: 1, Name: 'dartvm.exe' }]) };
  });
  assert.deepEqual(table, [{ pid: 2, parentPid: 1, name: 'dartvm.exe' }]);
  assert.deepEqual(readWindowsProcessTable(() => ({ status: 0, stdout: '[]' })), []);
  for (const result of [
    { status: 1, stderr: 'CIM access denied' },
    { status: 0, stdout: 'invalid JSON' },
    { status: 0, stdout: '{}' },
    { status: 0, stdout: '[{"ProcessId":2}]' },
    { error: new Error('spawn timed out') },
  ]) {
    assert.throws(() => readWindowsProcessTable(() => result));
  }
});

test('TUI dry runs never send keys or close panes', async () => {
  const f = fixture({ pane: ownedPane(), text: ready, running: true });
  for (const cmd of ['reload', 'restart', 'quit', 'stop']) assert.equal(await f.execute([cmd]), 0);
  assert.ok(!f.calls.some(args => ['send-text', 'send-keys', 'close'].includes(args[1])));
});

test('TUI startup command failure is propagated without duplicate launch or closing user work', async () => {
  const f = fixture({ invokeHerdr: () => fail('session_unavailable', 'TUI offline') });
  assert.equal(await f.execute(['start']), 2);
  assert.equal(f.messages.at(-1), 'TUI offline');
  assert.ok(!f.calls.some(args => args[1] === 'create'));
});

test('real TUI integration uses an isolated session and a fake Flutter process', { skip: process.env.KIRA_TEST_TUI !== '1' || process.platform !== 'win32' }, async () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'kira-tui-test-'));
  const session = 'kira-test-' + process.pid;
  const env = { ...process.env, HERDR_CONFIG_PATH: path.join(dir, 'config.toml'), HERDR_SOCKET_PATH: path.join(dir, 'test.sock') };
  delete env.HERDR_PANE_ID;
  delete env.HERDR_WORKSPACE_ID;
  delete env.HERDR_TAB_ID;
  const script = path.join(dir, 'flutter.cjs');
  writeFileSync(script, `process.stdin.setRawMode(true);
process.stdin.on('data', data => { for (const k of data.toString()) {
  if (k === 'r') console.log('Reloaded 1 library in 20ms.');
  if (k === 'R') console.log('Restarted application in 30ms.');
  if (k === 'q') process.exit(0);
}});
console.log('Flutter run key commands.');`);
  const server = spawn('herdr', ['--session', session, 'server'], { env, stdio: 'ignore', windowsHide: true });
  const call = args => spawnSync('herdr', ['--session', session, ...args], { env, encoding: 'utf8', timeout: 10000 });
  const messages = [];
  const driver = createDriver({
    root, windows: true, env: { KIRA_HERDR_BACKEND: 'tui' },
    invoke: () => { throw new Error('TUI must not call hc'); },
    invokeApp: () => { throw new Error('TUI must not call app'); },
    invokeHerdr: args => {
      if (args[0] === 'pane' && args[1] === 'run') {
        let decoded = Buffer.from(args[3].split(' ').at(-1), 'base64').toString('utf16le');
        const fake = `& '${process.execPath.replaceAll("'", "''")}' '${script.replaceAll("'", "''")}'`;
        decoded = decoded.replace(/& cmd.exe \/d \/s \/c '[^']+'/, fake);
        args = [...args.slice(0, 3), 'powershell.exe -NoProfile -NonInteractive -EncodedCommand ' + Buffer.from(decoded, 'utf16le').toString('base64')];
      }
      return call(args);
    },
    output: { log: value => messages.push(value), error: value => messages.push(value) },
  });
  try {
    for (let i = 0; i < 40; i++) {
      const probe = call(['workspace', 'list']);
      if (probe.status === 0) break;
      if (i === 39) throw new Error(probe.stderr);
      await delay(100);
    }
    for (const args of [['start'], ['start', '--wait'], ['has'], ['reload', '--yes'], ['restart', '--yes'], ['quit', '--yes'], ['log', '30'], ['stop', '--yes']]) {
      assert.equal(await driver.execute(args), 0, args.join(' ') + '\n' + messages.join('\n'));
    }
  } finally {
    call(['server', 'stop']);
    if (server.exitCode === null) await new Promise(resolve => server.once('exit', resolve));
    rmSync(dir, { recursive: true, force: true });
  }
});

test('TUI command uses the exact device and does not embed project paths or print auth values', async () => {
  const f = fixture({ env: { COPY_AUTH_KEY: 'test_key', KIRA_DEVICE: 'emulator-5678' } });
  assert.equal(await f.execute(['start']), 0);
  const command = f.calls.find(args => args[1] === 'run')[3];
  const decoded = Buffer.from(command.split(' ').at(-1), 'base64').toString('utf16le');
  assert.ok(decoded.includes('flutter run -d emulator-5678 --dart-define=COPY_AUTH_KEY=test_key'));
  assert.ok(!decoded.includes(root));
  assert.ok(!f.messages.join('\n').includes('test_key'));
});
