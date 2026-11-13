#!/usr/bin/env node
/**
 * kira 运行管理：通过 Herdr Core（hc）托管 flutter run。
 * 用法见同目录 SKILL.md；不依赖第三方 Node 包。
 */

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripVTControlCharacters } from 'node:util';
import { createTuiBackend } from './tui_backend.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const NAME = 'kira';
const READY = /Flutter run key commands\.|A Dart VM Service/;
const ERRORS = /Unhandled Exception|\bError:|EXCEPTION|Hot reload was rejected|Reloading failed|Restart failed/i;

function outputLines(text) {
  return stripVTControlCharacters(text).replace(/\r/g, '').split('\n').filter(line => line.trim());
}

// 终端会滚屏；只检查本次按键新增的输出，避免旧异常或旧 Reloaded 误判。
function newOutput(before, after) {
  const oldLines = outputLines(before);
  const lines = outputLines(after);
  let prefix = 0;
  while (prefix < Math.min(oldLines.length, lines.length) && oldLines[prefix] === lines[prefix]) prefix++;
  for (let n = Math.min(oldLines.length, lines.length); n > 0; n--) {
    if (oldLines.slice(-n).join('\n') === lines.slice(0, n).join('\n')) {
      return lines.slice(Math.max(n, prefix)).join('\n');
    }
  }
  return lines.slice(prefix).join('\n');
}

export function createDriver({
  invoke = args => spawnSync('hc', args, { encoding: 'utf8', windowsHide: true }),
  invokeApp = args => spawnSync('herdr-app', args, { encoding: 'utf8', windowsHide: true }),
  invokeHerdr = args => spawnSync('herdr', args, { encoding: 'utf8', windowsHide: true }),
  root = ROOT,
  env = process.env,
  windows = process.platform === 'win32',
  output = console,
} = {}) {
  const normalize = value => {
    const normalized = path.resolve(value).replace(/\\/g, '/');
    return windows ? normalized.toLowerCase() : normalized;
  };
  const project = normalize(root);
  const device = env.KIRA_DEVICE || 'windows';
  const authKey = (env.COPY_AUTH_KEY || '').trim();
  const redact = value => authKey ? String(value).replaceAll(authKey, '[REDACTED]') : String(value);

  let backend = 'app';
  const tui = createTuiBackend({ invoke: invokeHerdr, root, project, device, target: env.KIRA_TARGET, authKey, windows, env, newOutput, output });

  function selectBackend(requested) {
    if (!['auto', 'app', 'tui'].includes(requested)) throw new Error('后端必须为 auto、app 或 tui');
    if (requested !== 'auto') return requested;
    if (env.HERDR_ENV === '1' && env.HERDR_PANE_ID) return 'tui';
    if (env.HC_TERMINAL_ID) return 'app';
    const probe = invokeApp(['ls']);
    if (!probe.error && probe.status === 0) return 'app';
    const other = invokeHerdr(['workspace', 'list']);
    if (!other.error && other.status === 0) return 'tui';
    throw new Error(`没有可连接的 Herdr 后端。app: ${probe.error?.message || probe.stderr || probe.stdout}; TUI: ${other.error?.message || other.stderr || other.stdout}`);
  }

  function decode(result, args, waiting) {
    if (result.error) throw result.error;
    let data;
    try {
      data = JSON.parse(result.stdout || '');
    } catch {
      throw new Error(result.stderr || result.stdout || `hc ${args[0]} 未返回 JSON（退出码 ${result.status}）`);
    }
    if (data.error || (result.status !== 0 && !(waiting && data.reason))) {
      throw new Error(data.error?.message || result.stderr || JSON.stringify(data));
    }
    return data;
  }

  function hc(args, { waiting = false } = {}) {
    const result = (backend === 'tui' ? tui.invoke : invoke)([args[0], '--json', ...args.slice(1)]);
    return result instanceof Promise ? result.then(value => decode(value, args, waiting)) : decode(result, args, waiting);
  }

  function app(args) {
    const result = invokeApp(args);
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(result.stderr || result.stdout || '无法调用 Herdr，请先打开 Herdr');
    const data = JSON.parse(result.stdout);
    if (data.error) throw new Error(data.error.message || String(data.error));
    return data;
  }

  function workspace() {
    const data = app(['ls']);
    if (!Array.isArray(data.spaces)) throw new Error('herdr-app ls 返回的 spaces 不是列表');
    const matches = data.spaces.filter(space => space.machine == null && space.name?.toLowerCase() === NAME);
    // 同名时优先当前工作区，再选原工作区，避开旧 driver 创建的固定 ID。
    const selected = matches.find(space => space.active) || matches.find(space => space.id !== NAME) || matches[0];
    if (selected && typeof selected.id !== 'string') throw new Error('Herdr 工作区没有有效 ID');
    output.log(selected ? `复用工作区 "${NAME}" (${selected.id})，创建新的运行 tab。` : `没有本机 "${NAME}" 工作区，创建新的工作区与运行 tab。`);
    return selected?.id || NAME;
  }

  function nameTab(t) {
    const name = { win: 'run-win', mumu: 'run-mumu', emu: 'run-emu' }[env.KIRA_TARGET] ||
      { windows: 'run-win', win: 'run-win', '127': 'run-mumu', emu: 'run-emu' }[device.toLowerCase()] || `run-${device}`;
    // Herdr 异步接入终端，短暂重读布局找到其 tab；不等待 Flutter 编译。
    for (let attempt = 0; attempt < 8; attempt++) {
      const data = app(['ls']);
      if (!Array.isArray(data.spaces)) throw new Error('herdr-app ls 返回的 spaces 不是列表');
      const tab = data.spaces.filter(space => space.machine == null).flatMap(space => space.tabs || [])
        .find(tab => tab.terminals?.some(terminal => terminal.terminal === t.address));
      if (!tab) continue;
      if (typeof tab.id !== 'string') throw new Error('运行 tab 没有有效 ID');
      if (tab.name !== name) app(['do', 'tab.rename', '--id', tab.id, '--name', name]);
      output.log(`运行 tab: ${name}`);
      return;
    }
    throw new Error(`终端 ${t.address} 已后台启动，但尚未接入 Herdr，未能命名运行 tab；请勿重复启动`);
  }

  function terminal() {
    const list = hc(['ls', '--all', '--label', `kira.project=${project}`, '--label', 'kira.role=run']);
    if (!Array.isArray(list.terminals)) throw new Error('hc ls 返回的 terminals 不是列表');
    const addressPattern = backend === 'tui' ? /^w\d+:p\d+$/ : /^t[0-9a-z]+$/;
    const owned = list.terminals.filter(t => addressPattern.test(t.address) && normalize(t.cwd) === project);
    const live = owned.filter(t => t.state === 'live');
    if (live.length > 1) throw new Error('找到多个 kira 运行终端，请先检查 hc ls，避免控制错误进程');
    const selected = live[0] || owned.at(-1);
    return selected ? hc(['get', selected.address]) : null;
  }

  function isFlutter(t) {
    // Herdr 在终端丢失后可能恢复为 shell；此时不能把 r / R 发给 shell。
    return t?.state === 'live' && Array.isArray(t.argv) &&
      t.argv.some(arg => /(?:^|[\\/\s])flutter(?:\.bat)?(?:\s+run|$)/i.test(arg));
  }

  function ready(t, text) {
    return t.labels?.['kira.ready'] === 'true' || READY.test(text);
  }

  function rememberReady(t) {
    if (t.labels?.['kira.ready'] !== 'true') {
      hc(['label', t.address, 'kira.ready=true']);
      t.labels = { ...t.labels, 'kira.ready': 'true' };
    }
  }

  function read(t, lines = 200) {
    const data = hc(['read', t.address, '--lines', String(lines)]);
    if (typeof data.text !== 'string') throw new Error('hc read 未返回终端文本');
    if (isFlutter(t) && READY.test(data.text)) rememberReady(t);
    return data.text;
  }

  function show(text, lines = 20) {
    output.log(outputLines(redact(text)).slice(-lines).join('\n') || '(空)');
  }

  function wait(t, marker, seconds) {
    const args = ['wait', t.address, '--timeout', String(seconds)];
    if (marker) args.push('--output', marker);
    return hc(args, { waiting: true });
  }

  function has() {
    const alive = isFlutter(terminal());
    output.log(alive ? 'ALIVE' : 'DEAD');
    return alive ? 0 : 1;
  }

  function status() {
    const t = terminal();
    const alive = isFlutter(t);
    output.log(`${alive ? 'ALIVE' : 'DEAD'} — Herdr 终端 "${NAME}"${t ? ` (${t.address}, ${t.state})` : ' 不存在'}`);
    if (t) {
      if (t.state === 'finished') output.log(`退出码: ${t.exit_code ?? '未知'}；原因: ${t.reason ?? '未知'}`);
      if (t.state === 'live' && !alive) output.log('终端已不是 flutter run；冷启动前先 stop --yes 清理。');
      show(read(t, 60), 25);
    }
    return alive ? 0 : 1;
  }

  function log(n) {
    if (!Number.isSafeInteger(n) || n < 1) throw new Error('log 行数必须为正整数');
    const t = terminal();
    if (!t) {
      output.error('DEAD — 没有 kira 运行日志');
      return 1;
    }
    show(read(t, n), n);
    return 0;
  }

  async function waitReady(t) {
    let current = hc(['get', t.address]);
    let text = read(current);
    if (!ready(current, text) && isFlutter(current)) {
      await wait(t, 'Flutter run key commands.', 300);
      current = hc(['get', t.address]);
      text = read(current);
    }
    show(text);
    if (ready(current, text) && isFlutter(hc(['get', t.address]))) {
      rememberReady(current);
      output.log('✓ Flutter 就绪，可热重载。');
      return 0;
    }
    output.error('Flutter 尚未就绪或已退出；运行 status / log 查看实际原因。超时后进程仍可能在编译，请勿重复启动。');
    return 1;
  }

  function start(opts) {
    if (!/^[a-z0-9_.:-]+$/i.test(device)) throw new Error('KIRA_DEVICE 含有不支持的字符');
    if (authKey && !/^[a-z0-9_-]+$/i.test(authKey)) throw new Error('COPY_AUTH_KEY 含有不支持的字符');
    const existing = terminal();
    if (existing?.state === 'live') {
      if (!isFlutter(existing)) throw new Error('kira 终端已恢复为 shell；先 stop --yes，再冷启动');
      output.log(`复用 Herdr 终端 ${existing.address}。如需切换设备，先 stop --yes。`);
      return opts.wait ? waitReady(existing) : 0;
    }
    const flutter = ['flutter', 'run', '-d', device];
    // hc 使用 core 的环境，不继承这次调用临时设置的环境变量。
    // 编译期注入兼容 Windows 和 Android；输出中不显示密钥。
    if (authKey) flutter.push(`--dart-define=COPY_AUTH_KEY=${authKey}`);
    const command = windows ? ['cmd.exe', '/d', '/s', '/c', flutter.join(' ')] : flutter;
    const spaceId = backend === 'app' ? workspace() : null;
    output.log(`创建 Herdr 终端 "${NAME}"：flutter run -d ${device}`);
    const t = hc([
      'run', '--bg', '--outlive-parent', '--no-notify', '--name', NAME, '--cwd', root,
      '--label', `kira.project=${project}`, '--label', 'kira.role=run',
      // space 标签使用实际 ID；省略 tab 标签，让 Herdr 在该工作区创建新 tab。
      '--label', `herdr.space=${spaceId}`,
      '--', ...command,
    ]);
    if (typeof t.address !== 'string') throw new Error('hc run 未返回终端地址');
    if (backend === 'app') nameTab(t);
    if (!opts.wait) {
      output.log(`已后台启动 (${t.address})。查看进度: node .claude/skills/run-kira/driver.mjs log 40`);
      return 0;
    }
    return waitReady(t);
  }

  async function interactive(key, label, marker, opts) {
    const t = terminal();
    if (!isFlutter(t)) {
      output.error(`DEAD — 没有可控制的 flutter run，无法${label}。`);
      return 1;
    }
    if (!opts.yes) {
      output.log(`将执行${label}，未传 --yes，已跳过。`);
      return 0;
    }
    const before = read(t);
    if (key !== 'q' && !ready(t, before)) {
      output.error('Flutter 尚未就绪，未发送按键；先查看 log。');
      return 1;
    }
    hc(['keys', t.address, key === 'R' ? 'shift+r' : key]);
    let after = read(t);
    let fresh = newOutput(before, after);
    if (key === 'q') {
      if (hc(['get', t.address]).state === 'live') await wait(t, null, 30);
      after = read(t);
      show(after);
      if (hc(['get', t.address]).state === 'finished') {
        output.log('应用已退出，终端记录保留供 log 查询。');
        return 0;
      }
    } else {
      if (!ERRORS.test(fresh) && !marker.test(fresh)) {
        await wait(t, key === 'r' ? 'Reloaded ' : 'Restarted application', 60);
        after = read(t);
        fresh = newOutput(before, after);
      }
      show(after);
      if (ERRORS.test(fresh)) {
        output.error('⚠ 本次操作出现异常或被拒绝，请按上方实际输出排查。');
        return 2;
      }
      if (marker.test(fresh) && isFlutter(hc(['get', t.address]))) {
        output.log(`✓ ${label}完成。`);
        return 0;
      }
    }
    output.error(`已发送${label}按键，但未确认完成；请查看 status / log，不要直接重复发送。`);
    return 1;
  }

  async function stop(opts) {
    const t = terminal();
    if (!t) {
      output.log('kira 终端不存在，无需停止。');
      return 0;
    }
    if (!opts.yes) {
      output.log(`将停止并清理 kira 终端 ${t.address}，未传 --yes，已跳过。`);
      return 0;
    }
    if (backend === 'tui') {
      hc(['rm', t.address]);
      output.log(`已停止并清理 TUI pane ${t.address}。`);
      return 0;
    }
    if (t.state === 'live') {
      hc(['kill', t.address]);
      if (hc(['get', t.address]).state === 'live') await wait(t, null, 30);
      if (hc(['get', t.address]).state !== 'finished') throw new Error('终端尚未退出，未清理记录');
    }
    hc(['rm', t.address]);
    output.log(`已停止并清理 kira 终端 ${t.address}。`);
    return 0;
  }

  function send(keys, opts) {
    if (!keys.length) throw new Error('send 需要至少一个按键参数');
    const t = terminal();
    if (!isFlutter(t)) throw new Error('没有可控制的 flutter run');
    const namedKeys = keys.map(key => /^[A-Z]$/.test(key) ? `shift+${key.toLowerCase()}` : key);
    hc(['keys', t.address, ...namedKeys, ...(opts.enter ? ['enter'] : [])]);
    output.log(`已发送按键: ${keys.join(' ')}`);
    return 0;
  }

  return {
    async execute(argv) {
      try {
        argv = [...argv];
        const backendIndex = argv.indexOf('--backend');
        const requested = backendIndex < 0 ? env.KIRA_HERDR_BACKEND || 'auto' : argv[backendIndex + 1];
        if (backendIndex >= 0) argv.splice(backendIndex, 2);
        backend = selectBackend(requested);
        if (argv.includes('--wait') && argv.includes('--no-wait')) throw new Error('--wait 与 --no-wait 不能同时使用');
        const opts = { yes: argv.includes('--yes'), wait: argv.includes('--wait'), enter: argv.includes('--enter') };
        const [cmd, ...rest] = argv.filter(arg => !['--yes', '--wait', '--no-wait', '--enter'].includes(arg));
        switch (cmd) {
          case 'has': return has();
          case 'status': return status();
          case 'log': return log(Number(rest[0] || '40'));
          case 'start': return await start(opts);
          case 'reload': return await interactive('r', '热重载 (r)', /\bReloaded\s/, opts);
          case 'restart': return await interactive('R', '热重启 (R)', /Restarted application/, opts);
          case 'quit': return await interactive('q', '退出应用 (q)', null, opts);
          case 'stop': return await stop(opts);
          case 'send': return send(rest, opts);
          default: throw new Error('用法见 .claude/skills/run-kira/SKILL.md');
        }
      } catch (error) {
        output.error(redact(error.message));
        return 2;
      }
    },
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await createDriver().execute(process.argv.slice(2));
}
