# 开发与构建指南

[← 返回项目首页](../README.md)

本文汇集环境准备、仓库结构与构建入口。命令在项目根目录执行；贡献要求见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 支持平台与技术栈

- HarmonyOS NEXT，项目以 API 26 为当前开发基线；应用 target/compatible 与 native ABI 工具链分别核对，API 23 用于历史与兼容验证。
- ArkTS + ArkUI 声明式 UI，使用 HarmonyOS 原生 Kit。
- C/C++ NAPI 扩展承载 FreeRDP、VNC、音视频、渲染和输入桥接。
- Rust 承载 RustDesk 协议桥和 SSH 终端相关逻辑。
- 构建系统为 DevEco Studio Hvigor；当前产物覆盖 ARM64 与 x86_64 原生库。

## 架构

```text
ArkUI pages/components
        │
        ├── services / policies / RDB / cloud coordination
        │
        └── rdpnapi (NAPI boundary)
              ├── FreeRDP / WinPR ── RDP
              ├── rustdesk_ffi ───── RustDesk
              ├── libssh2 / terminal core ── SSH/SFTP
              ├── VNC adapter
              ├── Moonlight / Sunshine runtime
              └── decoder / renderer / audio / input bridges
```

协议会话、渲染、音频、输入、剪贴板和文件传输保持明确边界。可选能力失败
不应破坏已经建立的桌面会话；云同步和加密写入必须先确认本地事务成功，
再更新缓存或请求推送。

## 仓库结构

| 路径 | 用途 |
|---|---|
| `AppScope/` | 应用级清单、版本与资源 |
| `entry/src/main/ets/` | ArkTS 页面、组件、模型、服务和策略 |
| `entry/src/main/cpp/` | NAPI、协议适配、渲染、音视频与原生测试 |
| `rustdesk_ffi/` | RustDesk Rust FFI、协议会话与 Rust 测试 |
| `freerdp/` | 指向本仓库公开 `freerdp-ohos` 基线的 FreeRDP 子模块；OHOS 差异位于 `patches/freerdp-ohos/` |
| `scripts/` | 依赖构建、SBOM、合规和 clean-clone 脚本 |
| `docs/compliance/` | SPDX SBOM、来源、发布门禁、回滚和开源合规记录 |
| `LICENSES/` | 项目与第三方许可证文本 |

## 获取源码

```powershell
git clone --recurse-submodules https://github.com/Mydstiny/RemoteDesktopHarmonyOS.git
Set-Location RemoteDesktopHarmonyOS
```

如果已普通 clone，执行 `git submodule update --init --recursive`。FreeRDP
公开基线位于同一 GitHub 仓库的 `freerdp-ohos` 分支；主分支以 gitlink
固定基线，并通过仓库内有序 patch 系列重建经过复核的 OHOS 源码 tree。

## macOS 环境

```sh
source scripts/macos_env.sh
```

`scripts/macos_env.sh` 会自动发现 DevEco Studio SDK、内置 JBR/Java、
Node/Hvigor/ohpm、OHOS LLVM/CMake/Ninja 和 rustup 管理的 cargo/rustc。它只
设置当前 shell，不会写入私有配置；合规门禁需要 PowerShell 7（`pwsh`）。

## 本地私有配置

仓库不会跟踪签名证书、口令、AGConnect secret、API key、本机 SDK 路径
或真实用户数据。首次构建时按示例创建本地文件：

- `build-profile.example.json5` → 本地 `build-profile.json5`
- `local.properties.example` → 本地 `local.properties`
- `entry/src/main/resources/rawfile/agconnect-services.example.json` → 本地
  `agconnect-services.json`

真实值只能保存在本机安全路径或 CI secrets。不要把这些文件加入 Git，
也不要在 issue、日志或截图中公开它们。

## 构建依赖

1. 安装 DevEco Studio 和 HarmonyOS API 26 SDK；按项目脚本配置保留兼容目标所需的 native SDK。
2. 安装 Git、PowerShell 7、Rust/Cargo，以及项目脚本所需的 C/C++ 工具链。
3. 准备上述本地私有配置。
4. 首次 clean clone 或 RustDesk/Opus 输入变化后构建双 ABI 原生依赖：

```text
bash scripts/build_opus_ohos.sh all
bash scripts/build_rustdesk_ffi_ohos.sh all
```

macOS 可先执行 `source scripts/macos_env.sh`。SDK 位置由项目脚本根据本机安装与
`DEVECO_SDK_HOME` / `OHOS_SDK_HOME` 等环境变量解析；脚本兼容 macOS 的
`shasum` 和 CPU 并行数。Hvigor 使用完整 HarmonyOS SDK，CMake / Rust 使用
native 工具链，二者分别核对。保留 API 23 兼容目标时，应选择相应的 native SDK，
不能仅根据 HarmonyOS SDK 版本推断原生 ABI 的兼容性。

FreeRDP、FFmpeg 或其他原生依赖变化时，使用 `scripts/` 下对应的 OHOS 构建
脚本，并同步更新来源、许可证、SBOM 和产物哈希。

## 构建 HAP

Windows 使用 DevEco 自带的 `hvigorw.js` / `hvigorw.bat`，执行与下方相同的两项任务、参数和 `--no-daemon`。根据本机安装位置选择启动器，不覆盖已配置的 SDK 环境。

在 macOS shell 中：

```sh
source scripts/macos_env.sh
hvigorw --mode module -p module=entry -p product=default default@OhosTestCompileArkTS \
  --analyze=normal --parallel --incremental --no-daemon
hvigorw --mode module -p module=entry -p product=default assembleHap \
  --analyze=normal --parallel --incremental --no-daemon
```

常见输出目录：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
entry/build/default/outputs/default/entry-default-signed.hap
```

签名产物仅属于本地私有发布流程，不得上传到本仓库的 unsigned 测试
Release。

## 测试与验证

```powershell
# 开源合规轻量门禁
pwsh -File scripts/verify_open_source_release.ps1 -Mode Light
```

其他主要验证入口：

- ArkTS：`default@OhosTestCompileArkTS`（主代码）与 `ohosTest@OhosTestCompileArkTS`（单元测试，只编译）。单元测试与应用共用沙箱，请勿在装有真实数据的设备上运行。
- Native：项目生成的 `rdp_native_tests` 测试程序。
- Rust：在 `rustdesk_ffi/` 执行 `cargo test --lib --no-default-features`。
- Clean clone：`scripts/verify_clean_clone_build.ps1`。
- 正式发布：`scripts/verify_open_source_release.ps1 -Mode Release`。

Release 模式还要求凭据轮换、完整设备矩阵和私有构建配置，不能用一次
Light 通过或一次本地 HAP 构建代替。

## 贡献流程

1. Fork 本仓库并基于 `main` 创建分支。
2. 修改后至少通过上面的两项 Hvigor 构建、单元测试编译和 `verify_open_source_release.ps1 -Mode Light`。
3. 提交 Pull Request，说明改动、验证方式和涉及的设备/协议。

依赖、proto、许可证和构建输入变化必须同步更新 SBOM、NOTICE、provenance 与哈希。
