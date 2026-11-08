---
name: run-kira
description: 启动、停止、热重载 / 热重启 kira。用户要求运行项目、刷新运行中的 app、查看运行日志或停止应用时使用；支持 Windows、MuMu 与 Android emulator。仅当前项目生效。
---

# run-kira

使用 **Herdr Core（`hc`）** 托管 `flutter run`。终端名固定为 `kira`，通过项目路径与运行角色标签识别，跨会话复用；`--outlive-parent` 让它在当前编码会话结束后继续运行。

冷启动先用 `herdr-app ls` 按**名称**查找本机 `kira` 工作区，使用其实际 ID；同名时优先当前工作区，其次原工作区而非旧 driver 创建的固定 ID。只设置 `herdr.space=<实际 ID>`，省略 `herdr.tab`，让 Herdr 在已有工作区创建新 tab。仅在本机没有同名工作区时新建；查询失败须报错，不能默默新建重复工作区。已有 Flutter 进程则直接复用，不新建 tab。新 tab 按设备命名为 `run-win`（Windows）、`run-mumu`（MuMu）、`run-emu`（Android emulator），其他设备用 `run-<device>`；按新终端地址定位 tab 后调用 `tab.rename`，不改当前编码 tab。

所有命令在仓库根目录执行，入口为 `.claude/skills/run-kira/driver.mjs`。依赖 Node.js ≥ 18、`hc`、`herdr-app`、Flutter 与目标平台构建工具；创建运行 tab 时 Herdr 窗口须已打开，已有进程的日志/按键控制不依赖窗口。**旧版 `herdr` 与新版 `hc` 不互换**。具体 CLI 参数以本机 `hc <command> --help` 为准，窗口行为见 `~/.config/herdr-app/AGENTS.md`。

## 操作流程

1. 执行 `node .claude/skills/run-kira/driver.mjs has`。
   - `ALIVE` / 退出码 0：已有托管的 Flutter 进程，按获准的操作继续。
   - `DEAD` / 退出码 1：执行 `status` / `log` 排查；仅在用户明确要求启动或批准冷启动后执行 `start`。代码修改本身不授权冷启动。
   - 退出码 2：`hc` 调用或数据异常，先处理实际错误，不能当作 `DEAD`。
2. 代码修改完成后按项目规范验证；应用已运行且允许刷新时执行 `reload --yes`，需要重置 Dart 状态时用 `restart --yes`。
3. 以 driver 检查到的**本次完成标记**和日志判断结果。只有 `✓ ...完成` 才确认热重载/热重启成功；错误、拒绝、超时或进程退出须如实报告。未完成时先查看日志，不重复发键或重复启动。

`reload` / `restart` / `quit` / `stop` 未带 `--yes` 时只预览，不执行。`--yes` 是 driver 的执行开关，不替代用户授权。

## 命令

```bash
node .claude/skills/run-kira/driver.mjs has
node .claude/skills/run-kira/driver.mjs status
node .claude/skills/run-kira/driver.mjs log 60
node .claude/skills/run-kira/driver.mjs start
node .claude/skills/run-kira/driver.mjs start --wait
node .claude/skills/run-kira/driver.mjs reload --yes
node .claude/skills/run-kira/driver.mjs restart --yes
node .claude/skills/run-kira/driver.mjs quit --yes
node .claude/skills/run-kira/driver.mjs stop --yes
```

- `start` 默认设备为 `windows`，**默认异步返回**：只等后台进程与运行 tab 创建、命名，不等 Flutter 编译/就绪；返回 0 仅表示进程创建或已有进程复用。`--no-wait` 保留为兼容参数，与默认行为相同。需要等待时显式传 `--wait`（最多 5 分钟），已有进程直接复用并等待，不重复创建。
- 异步启动后用 `log` 确认出现 `Flutter run key commands.` / `A Dart VM Service` 再刷新；也可执行 `start --wait` 等待已有进程就绪。就绪状态保存为终端标签，日志滚屏后仍能控制；恢复为 shell 时此标签不代表 Flutter 存活。
- driver 通过 `hc wait --output` 等待完成，不用 sleep 或忙循环轮询。等待超时不会终止后台进程。
- `reload` 发 `r`，保留状态；`restart` 发大写 `R`，重置 Dart 状态。driver 等待本次完成最多 60 秒。
- `quit` 发 `q`，等待退出并保留终端记录，`log` 仍可读取退出日志；下一次 `start` 创建新终端。
- `stop` 只 kill / rm 本项目带运行标签的终端，也可清理已退出或恢复为 shell 的记录。它不会停止整个 core 或其他工作终端。
- `KIRA_DEVICE` 指定 `flutter -d` 参数。`COPY_AUTH_KEY` 如有设置，会作为 `--dart-define` 注入 Windows / Android 构建，日志隐藏其值；不要依赖 core 继承调用方临时设置的环境变量。

## 人工启动与设备准备

```powershell
.\scripts\run.ps1 win           # Windows：异步启动，Flutter 后台编译
.\scripts\run.ps1 mumu          # MuMu：准备设备后异步启动 Flutter
.\scripts\run.ps1 emu           # Android emulator：设备上线后异步启动 Flutter
.\scripts\run.ps1 win -Wait     # 显式等待 Flutter 就绪
.\scripts\run.ps1 -Log
.\scripts\run.ps1 -Stop
```

`run.ps1` 面向 Windows；脚本与 driver 均按自身位置推导仓库路径，不依赖安装盘符、用户名或调用时的工作目录。先准备目标设备，再停止旧的托管进程并冷启动；设备准备失败保留旧 app。模拟器启动与 ADB 连接仍须等待完成，Flutter 编译默认在后台进行；`-Wait` 才等待应用就绪，`-NoWait` 兼容旧用法。只想刷新时直接用 driver。

本机选项优先级：**命令行参数 → 环境变量 → `.claude/skills/run-kira/run.local.json` → 通用默认值**。本机 JSON 可用 `-ConfigPath` 指定，仅放下表设备字段，不入库。

| 参数 / JSON 字段 | 环境变量 | 无配置时 |
| --- | --- | --- |
| `MuMuManager` | `KIRA_MUMU_MANAGER` | 从 PATH 或系统 Program Files 查找；支持绝对路径或仓库相对路径 |
| `MuMuIndex` | `KIRA_MUMU_INDEX` | 实例 0 |
| `MuMuAdbAddr` | `KIRA_MUMU_ADB_ADDR` | `127.0.0.1:16384`，其他实例/版本需配置实际端口 |
| `EmulatorName` | `KIRA_EMULATOR_NAME` | Android SDK 的唯一 AVD；多个时明确选择，不猜个人设备名 |

可用 `-MuMuManager` / `-MuMuIndex` / `-MuMuAdbAddr` / `-EmulatorName` 临时覆盖配置。AVD 列表由 SDK 的 `emulator -list-avds` 查询（Flutter 的 `emulators` 不支持 `--machine`）；SDK 从 PATH、`ANDROID_SDK_ROOT` / `ANDROID_HOME`、adb 所在 SDK 或系统默认目录发现。启动后按 AVD 名匹配实际 serial，MuMu 使用完整 ADB 地址，避免 `127` / `emu` 前缀选错设备。脚本设置 `KIRA_DEVICE`（实际 serial）与 `KIRA_TARGET`（`win` / `mumu` / `emu`，用于 tab 命名）。

## 直接控制终端

优先用 driver，以便验证项目归属、Flutter 就绪与操作结果。需要人工接管时，从 `status` 获取**实际地址**（如 `t7`），避免按名字误控其他终端：

```bash
hc get t7 --json
hc read t7 --lines 60
hc keys t7 r
hc keys t7 shift+r
hc keys t7 q
hc attach t7
```

`hc attach` 后按 **Ctrl+\** 脱离，程序继续运行。单个 Flutter 命令用 `hc keys`，不是会粘贴文本并追加回车的 `hc send`；`hc keys R` 会转为小写，热重启须用 `shift+r`，driver 已自动转换。其他已获准的按键可通过 `driver.mjs send v` / `send h --enter` 发送。

## 共享边界与隐私

Git 只跟踪此目录的 `SKILL.md`、`driver.mjs`、`driver_test.mjs` 与 `run_script_test.mjs`；本机 JSON、日志、截图等其余文件继续忽略。共享文件不包含个人路径、工作区实际 ID 或真实账号/密钥值。新克隆需自行安装 Node.js ≥ 18、Herdr Core / Herdr app、Flutter 与对应平台工具；本 skill 不自动安装工具或修改全局配置。

`COPY_AUTH_KEY` 只从环境变量读取，未设置仍能运行，但相关接口登录入口不可用。driver 会隐藏输出中的值，但 `--dart-define` **不是秘密存储**：值会进入编译产物与 Herdr 的运行参数记录。不要把密码或访问令牌填入它，也不要提交运行时记录。仓库路径标签同样只保存在本机 Herdr 中。

## 修改 driver / 启动脚本后验证

```bash
KIRA_TEST_HC=1 node --test .claude/skills/run-kira/driver_test.mjs .claude/skills/run-kira/run_script_test.mjs
```

覆盖单测与真实 `hc` 集成；core 集成使用独立 `HC_SESSION` 和临时存储目录，运行模拟 Flutter 的 Node 进程。PowerShell 测试仅在 Windows 运行，模拟设备工具，覆盖跨目录调用、路径空格/单引号、配置优先级与 AVD 选择；需要 PowerShell 7（`pwsh`）。两类测试均不启动真实 app/模拟器、不停止用户的 core。只改此 skill / 脚本时无需 Flutter analyze。

## 故障与重建

- `DEAD` 但应用窗口还在：可能由普通终端或旧 psmux 启动，driver 不接管；由用户确认停止旧进程并批准迁移启动，不自动终止它。
- core / 电脑重启后，Herdr 可能只恢复一个 shell，**不会重跑 Flutter**；driver 将其视为 `DEAD`。先 `status` 看原因，获准后 `stop --yes` → `start`。
- 未就绪或提前退出：`log 100` 查看编译错误与异常栈。缺平台工具时按项目 `docs/platform-build.md` 排查。
- 热重载被拒：按实际错误判断是否需要 `restart`。原生代码、插件或依赖变化通常需要 `stop` → 重新构建 / `start`，`R` 不会重编译原生代码。
- `hc` 不在 PATH：修复 Herdr Core 安装或 PATH；安装 / 更新须经用户同意。不要改为调用旧 `herdr`，也不要重启用户的整个 core。
