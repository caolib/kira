# 正式版发布清单

`.github/workflows/release.yml` 的 `release` job 在安装包发布成功后，通过 `scripts/generate_release_manifest.py` 的 `publish_manifest` 生成并上传 `release.json`，供官网或外部脚本读取。应用内更新仍使用现有 GitHub Releases API，不改客户端协议。

## 访问入口

- 最新版：`https://github.com/caolib/kira/releases/latest/download/release.json`
- 指定版本：`https://github.com/caolib/kira/releases/download/<tag>/release.json`

每个正式 Release 保留独立附件。不回填历史版本，不覆盖 beta、测试或 `release-all.yaml` 全平台流程。最新入口跟随 GitHub 的 latest Release；如果 latest 是没有清单的历史版本或其他流程发布的版本，该入口会返回 404。

## 协议（schema_version = 1）

文件使用 UTF-8 JSON，安装包放在统一的 `assets` 数组中，不包含 `release.json` 自身。

| 顶层字段 | 类型 | 含义 |
| --- | --- | --- |
| `schema_version` | int | 清单协议版本，当前为 1 |
| `version` | string | 指定标签快照内的应用版本，不含 `v` 与构建号 |
| `build_number` | int | 同一快照内 `pubspec.yaml` 的构建号 |
| `tag` | string | 正式 Release 标签，如 `v1.7.6` |
| `name` | string | 实际 Release 标题 |
| `published_at` | string | 实际发布时间，ISO 8601、固定 UTC+8，含 `+08:00` 偏移 |
| `release_url` | string | GitHub Release 页面完整 URL |
| `release_notes` | string | 实际 Release 的完整 Markdown 正文，保留换行 |
| `assets` | array | 本次正式发布的全部安装包 |

| 安装包字段 | 类型 | 含义 |
| --- | --- | --- |
| `name` | string | 完整资产文件名 |
| `platform` | string | `android` 或 `windows` |
| `arch` | string | Android：`arm64-v8a` / `armeabi-v7a` / `x86_64`；Windows：`x64` |
| `size` | int | 文件大小，单位为字节 |
| `download_url` | string | GitHub 原始完整下载直链，不内置第三方镜像 |
| `sha256` | string | 64 位小写十六进制 SHA-256，不含算法前缀 |

时间转换保留实际发布时刻，例如 `2026-11-07T20:30:00Z` 表示为 `2026-11-08T04:30:00+08:00`，不是生成清单时的本地时间。

安装包元信息以远端实际上传的资产为准。优先使用 GitHub 提供的 SHA-256 digest；旧资产没有 digest 时，下载到独立临时目录，核对大小并流式计算 SHA-256。重跑时不使用重新构建的本地包代替已发布包。

## 发布与重试

1. 标签推送与手动发布都检出 `refs/tags/<tag>`；手动入口使用输入标签。创建前要求标签与 `pubspec.yaml` 版本一致，并通过 `--verify-tag` 禁止自动创建缺失标签。
2. 新 Release 要求本地包含全部 3 种 APK 和 Windows 安装包；发布后读取真实元信息，生成并上传清单。
3. 已存在的公开正式 Release 直接复用，不覆盖安装包。清单缺失时补传；已有清单与生成结果一致时跳过上传。
4. 包缺失、版本不一致、上传未完成或已有清单内容不同，均失败并保留远端现状，不自动删除或覆盖附件。网络、认证和权限错误不当作 Release 不存在。
5. 清单失败时 Actions 报错，但已公开的安装包不撤回；可重跑失败的 job。清单成功后，CI 预览渠道同步从正式 Release 下载同一 arm64 包，避免重建包与正式包不一致。

安装包公开与清单上传之间存在短暂间隔，消费者应允许暂时获取不到清单。SHA-256 校验不能替代安装包签名验证。

## 本地验证

所有命令在仓库根目录执行，仅模拟 GitHub 操作，不创建、修改或删除真实 Release：

```sh
python -I -m unittest discover -s test/scripts -p 'generate_release_manifest_test.py' -v
bash test/scripts/sync_release_to_ci_test.sh
```
