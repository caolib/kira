import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

export function readWindowsProcessTable(run = spawnSync) {
  // 只读 PID、父 PID 和名称，不读取可能包含密钥的命令行。
  const script = "$ErrorActionPreference = 'Stop'; $items = @(Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name); ConvertTo-Json -InputObject $items -Compress";
  const result = run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], {
    encoding: 'utf8', windowsHide: true, timeout: 10000,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(result.stderr || `Windows 进程查询失败（退出码 ${result.status}）`);
  const rows = JSON.parse(result.stdout);
  if (!Array.isArray(rows) || rows.some(row => !row ||
    !Number.isSafeInteger(row.ProcessId) || row.ProcessId < 0 ||
    !Number.isSafeInteger(row.ParentProcessId) || row.ParentProcessId < 0 ||
    typeof row.Name !== 'string')) throw new Error('Windows 进程查询返回了无效数据');
  return rows.map(row => ({ pid: row.ProcessId, parentPid: row.ParentProcessId, name: row.Name }));
}

function hasRuntimeDescendant(shellPid, processes) {
  const children = new Map();
  for (const process of processes) {
    if (!children.has(process.parentPid)) children.set(process.parentPid, []);
    children.get(process.parentPid).push(process);
  }
  const visited = new Set([shellPid]);
  const pending = [shellPid];
  while (pending.length) {
    for (const process of children.get(pending.pop()) || []) {
      if (visited.has(process.pid)) continue;
      visited.add(process.pid);
      // shell 包装本身不证明 Flutter 存活；node 用于隔离集成测试的模拟进程。
      if (/^(dart|dartvm|dartaotruntime|flutter|node)(\.exe)?$/i.test(process.name)) return true;
      pending.push(process.pid);
    }
  }
  return false;
}

// 将 TUI 独立运行时映射为 driver 使用的终端操作，所有控制均限定到自建 pane。
export function createTuiBackend({ invoke, root, project, device, target, authKey, windows, env, newOutput, output, readProcessTable = readWindowsProcessTable }) {
  const owner = createHash('sha256').update(project).digest('hex');
  const beforeInput = new Map();
  const response = data => ({ status: 0, stdout: JSON.stringify(data), stderr: '' });
  const tabName = { win: 'run-win', mumu: 'run-mumu', emu: 'run-emu' }[target] ||
    { windows: 'run-win', win: 'run-win', '127': 'run-mumu', emu: 'run-emu' }[device.toLowerCase()] || `run-${device}`;

  function call(args, { text = false } = {}) {
    const result = invoke(args);
    if (result.error) throw result.error;
    if (text && result.status === 0) return result.stdout || '';
    if (result.status === 0 && !(result.stdout || '').trim()) return {};
    let data;
    try { data = JSON.parse(result.status === 0 ? result.stdout : result.stderr || result.stdout); }
    catch { throw new Error(result.stderr || result.stdout || `herdr ${args[0]} 调用失败`); }
    if (result.status !== 0 || data.error) {
      const error = new Error(data.error?.message || result.stderr || JSON.stringify(data));
      error.code = data.error?.code;
      throw error;
    }
    if (!data.result) throw new Error('herdr 未返回 result');
    return data.result;
  }

  function snapshot() {
    const data = call(['pane', 'list']);
    if (!Array.isArray(data.panes)) throw new Error('herdr pane list 未返回 panes');
    return data.panes.filter(pane => pane.tokens?.kira_project === owner && pane.tokens?.kira_role === 'run');
  }

  function owned(id) {
    const pane = call(['pane', 'get', id]).pane;
    if (!pane || pane.tokens?.kira_project !== owner || pane.tokens?.kira_role !== 'run') {
      throw new Error('TUI pane 不属于此项目，拒绝控制');
    }
    return pane;
  }

  function read(id, lines = 200) {
    return call(['pane', 'read', id, '--source', 'recent-unwrapped', '--lines', String(lines)], { text: true });
  }

  function get(id) {
    const pane = owned(id);
    const tokens = pane.tokens;
    const text = read(id);
    const exit = text.match(new RegExp(`^KIRA_${tokens.kira_run}_EXIT_(-?\\d+)\\s*$`, 'm'));
    const info = call(['pane', 'process-info', '--pane', id]).process_info;
    if (!info) throw new Error('herdr pane process-info 未返回进程状态');
    const processes = info.foreground_processes || [];
    let running = processes.some(p => p.pid !== info.shell_pid && /^(dart|dartvm|dartaotruntime|flutter|node)(\.exe)?$/i.test(p.name));
    // pane 创建与命令入队不等于进程就绪；给命令启动一个有界窗口。
    const starting = Date.now() - Number(tokens.kira_started) < 15000;
    const sameTerminal = tokens.kira_terminal === pane.terminal_id;
    if (windows && sameTerminal && !exit && !running && !starting) {
      // Windows 的 foreground_processes 可能只有 shell；只沿此 pane 的
      // shell 子树查找运行时，不能拿其他终端的 Dart/Flutter 进程作存活证据。
      if (!Number.isSafeInteger(info.shell_pid) || info.shell_pid <= 0) throw new Error('TUI 未返回有效的 shell PID');
      running = hasRuntimeDescendant(info.shell_pid, readProcessTable());
    }
    const live = sameTerminal && !exit && (running || starting);
    return {
      address: id, cwd: root, state: live ? 'live' : 'finished',
      argv: live ? ['flutter', 'run', '-d', tokens.kira_device] : [],
      labels: { 'kira.ready': tokens.kira_ready || 'false' },
      exit_code: exit ? Number(exit[1]) : null,
      reason: !sameTerminal ? 'terminal_recovered' : exit ? 'exited' : live ? null : 'process_exited',
    };
  }

  function metadata(id, tokens) {
    const args = ['pane', 'report-metadata', id, '--source', 'kira-run'];
    for (const [key, value] of Object.entries(tokens)) args.push('--token', `${key}=${value}`);
    call(args);
  }

  function launch() {
    const data = call(['workspace', 'list']);
    if (!Array.isArray(data.workspaces)) throw new Error('herdr workspace list 未返回 workspaces');
    const matches = data.workspaces.filter(w => w.label?.toLowerCase() === 'kira');
    const workspace = matches.find(w => w.workspace_id === env.HERDR_WORKSPACE_ID) || matches.find(w => w.focused) || matches[0];
    const created = workspace
      ? call(['tab', 'create', '--workspace', workspace.workspace_id, '--cwd', root, '--label', tabName, '--no-focus'])
      : call(['workspace', 'create', '--cwd', root, '--label', 'kira', '--no-focus']);
    const pane = created.root_pane;
    if (!pane?.pane_id || !pane.terminal_id) throw new Error('TUI 创建响应没有 pane 身份信息，请检查工作区，不要重复启动');
    if (!workspace) call(['tab', 'rename', created.tab.tab_id, tabName]);
    const run = randomUUID().replaceAll('-', '');
    metadata(pane.pane_id, {
      kira_project: owner, kira_role: 'run', kira_terminal: pane.terminal_id,
      kira_run: run, kira_started: String(Date.now()), kira_device: device,
    });
    const flutter = `flutter run -d ${device}${authKey ? ` --dart-define=COPY_AUTH_KEY=${authKey}` : ''}`;
    // 独立 PowerShell 包装保证不依赖用户 pane 的默认 shell，退出标记区分残留 shell 与 Flutter。
    // EncodedCommand 仅处理转义，不是加密；命令值同样受 driver 的脱敏处理。
    let command;
    if (windows) {
      const script = `[Console]::WriteLine('KIRA_${run}_START'); & cmd.exe /d /s /c '${flutter}'; $code=$LASTEXITCODE; [Console]::WriteLine('KIRA_${run}_EXIT_'+$code); exit $code`;
      command = `powershell.exe -NoProfile -NonInteractive -EncodedCommand ${Buffer.from(script, 'utf16le').toString('base64')}`;
    } else {
      const script = `printf 'KIRA_${run}_START\\n'; ${flutter}; code=$?; printf 'KIRA_${run}_EXIT_%s\\n' "$code"; exit "$code"`;
      command = `sh -c '${script.replaceAll("'", "'\\''")}'`;
    }
    call(['pane', 'run', pane.pane_id, command]);
    output.log(`TUI 运行 tab: ${tabName} (${pane.pane_id})`);
    return { address: pane.pane_id };
  }

  async function wait(id, marker, seconds) {
    const deadline = Date.now() + seconds * 1000;
    const before = beforeInput.get(id);
    while (Date.now() < deadline) {
      const t = get(id);
      const text = read(id);
      const fresh = before === undefined ? text : newOutput(before, text);
      if (t.state === 'finished') return response({ reason: 'exit', ended: true, exit_code: t.exit_code });
      if (marker && (fresh.includes(marker) || /Hot reload was rejected|Reloading failed|Restart failed|Error:/.test(fresh))) {
        return response({ reason: 'output', ended: false });
      }
      await delay(250);
    }
    return response({ reason: 'timeout', ended: false });
  }

  return {
    invoke(args) {
      const [cmd, ...rest] = args.filter(arg => arg !== '--json');
      const id = rest[0];
      switch (cmd) {
        case 'ls': return response({ terminals: snapshot().map(p => get(p.pane_id)) });
        case 'get': return response(get(id));
        case 'read': owned(id); return response({ text: read(id, rest[rest.indexOf('--lines') + 1]), complete: true });
        case 'run': return response(launch());
        case 'label': owned(id); metadata(id, { kira_ready: 'true' }); return response({});
        case 'keys': {
          const t = get(id);
          if (t.state !== 'live') throw new Error('Flutter 已退出，未发送按键');
          beforeInput.set(id, read(id));
          for (const key of rest.slice(1)) {
            if (key === 'shift+r') call(['pane', 'send-text', id, 'R']);
            else if (key.length === 1) call(['pane', 'send-text', id, key]);
            else call(['pane', 'send-keys', id, key]);
          }
          return response({});
        }
        case 'wait': return wait(id, rest.includes('--output') ? rest[rest.indexOf('--output') + 1] : null, Number(rest[rest.indexOf('--timeout') + 1]));
        case 'kill': owned(id); call(['pane', 'close', id]); return response({});
        case 'rm': {
          try { owned(id); call(['pane', 'close', id]); }
          catch (error) { if (error.code !== 'pane_not_found') throw error; }
          return response({});
        }
        default: throw new Error(`TUI 后端不支持操作: ${cmd}`);
      }
    },
  };
}
