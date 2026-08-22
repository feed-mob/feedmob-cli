# FeedMob CLI macOS/Linux Homebrew 发行开发计划

状态：Proposed

日期：2026-08-21

目标版本：首个同时支持 macOS 与 Linux 的 `fm` Homebrew release

依赖：Token 安全加固 PR #5 合并后实施

## 1. 目标

把现有仅支持 macOS arm64/x86_64 的 Tebako/Homebrew 发布链路扩展为四个原生目标：

| Target ID | OS | CPU | GitHub Release asset | 首选构建环境 |
| --- | --- | --- | --- | --- |
| `macos-arm64` | macOS | arm64 | `fm-darwin-arm64.tar.gz` | GitHub-hosted Apple Silicon runner |
| `macos-x86_64` | macOS | x86_64 | `fm-darwin-x86_64.tar.gz` | GitHub-hosted Intel runner |
| `linux-arm64` | Linux GNU | arm64 | `fm-linux-arm64.tar.gz` | Ubuntu 22.04 arm64 runner |
| `linux-x86_64` | Linux GNU | x86_64 | `fm-linux-x86_64.tar.gz` | Ubuntu 22.04 x86_64 runner |

最终用户只需要 Homebrew 和私有 GitHub 访问权限，不需要预装 Ruby、Bundler、Gem 或 Tebako：

```sh
brew tap feed-mob/tap git@github.com:feed-mob/homebrew-tap.git
HOMEBREW_GITHUB_API_TOKEN="$(gh auth token)" brew install feed-mob/tap/fm
fm --json version
```

发布结果必须满足：

- 四个平台使用同一个 `fm` 版本和同一个 Formula。
- Formula 根据 OS 与 CPU 精确选择对应 Release asset。
- 每个压缩包只包含一个权限为 `0755` 的 `fm`。
- macOS 产物是正确架构的 Mach-O，正式发布前完成 Developer ID 签名和公证验收。
- Linux 产物是正确架构的 ELF，不含缺失动态库，并符合声明的 glibc 基线。
- 产物从无系统 Ruby/Gem 的最小环境启动并输出稳定 JSON。
- Linux 登录、状态读取和注销使用 PR #5 引入的加密本地凭据存储。
- 发布流程不把 GitHub Token、Apple 证书、API Token 或用户凭据写入产物、日志、Formula 或缓存。

## 2. 非目标

本计划不包含：

- Windows、Alpine/musl、FreeBSD 或 Homebrew Cask。
- PKG/DMG 安装器。
- 将 Formula 提交到 `homebrew/core`。
- 目标机器现场编译 Ruby 或安装 gem。
- 修改 Pixel 或 Time Off 服务端 API。
- 自动删除用户 Keychain 或 Linux 加密凭据；卸载后的凭据仍由 `fm ... auth logout` 管理。
- 未经单独批准创建真实 GitHub Release、创建/修改远端 Tap、上传签名证书或推送发布分支。

## 3. 关键技术决策

### 3.1 保留 Tebako fat standalone

继续使用当前 runtime-only staging root 和 Tebako fat 模式。Homebrew 只选择、下载、校验和安装上游二进制，不承担 Ruby 构建，因此这里发布的是预编译上游 archive，不是 Homebrew bottle。

保留 `script/prepare-release-root` 的最小内容边界：

```text
Gemfile
Gemfile.lock
exe/fm
lib/**
```

不得直接对仓库根目录执行 `tebako press`，避免测试和开发依赖中的 native extension 混入产物。

### 3.2 使用四个原生构建任务

正式产物必须在目标 OS/CPU 的原生 runner 上构建和运行验证。Rosetta、QEMU 和 Docker buildx 只能作为开发辅助，不能替代目标架构发布门禁。

初始 runner 建议：

| Target ID | `runs-on` 候选 | 备注 |
| --- | --- | --- |
| `macos-arm64` | `macos-15` | 发布前确认实际 runner 架构为 arm64 |
| `macos-x86_64` | `macos-15-intel` | 必须在原生 Intel 上执行 smoke |
| `linux-arm64` | `ubuntu-22.04-arm` | ARM runner 当前可用性需要在仓库中实测 |
| `linux-x86_64` | `ubuntu-22.04` | 首个 Linux spike 从此目标开始 |

每个 job 开始时输出但不依赖人工阅读：

```sh
uname -s
uname -m
```

脚本根据 `Target ID` 和实际 `RbConfig::CONFIG`/`uname` 双重验证，目标与 runner 不匹配时立即失败。

### 3.3 初始 Linux 兼容性基线

第一版先声明 Linux GNU/glibc 支持，建议基线为 Ubuntu 22.04 或兼容发行版。实际最低 glibc 版本必须由生成产物的 version requirement 扫描结果决定，不能只根据 runner 名称推断。

**实施记录（2026-08-22）：** 首次 dry-run 实测 Tebako 0.1.0 官方 Linux 工具（arm64 与 x86_64）要求 `GLIBC_2.36/2.38/2.39`，无法在 Ubuntu 22.04（glibc 2.35）上运行。基线因此确定为 Ubuntu 24.04 / `glibc_max = 2.39`，Linux runner 使用 `ubuntu-24.04` 与 `ubuntu-24.04-arm`。

**实施记录（2026-08-22，第二次修订）：** 第二次 dry-run 发现 tebako-runtime 0.15.9 的 Linux 版本 `--tebako-extract` 损坏（`File.lstat: /__tebako_memfs__`，noble 上两个架构均可复现；macOS 正常），press 流程无法继续。迁移到 Tebako 工具 v0.1.9 + runtime 0.16.4（image-era）后 Linux press 与完整凭据 smoke 全部通过；实测工具与产物均只需 `GLIBC_2.30`，基线回落为 Ubuntu 22.04 / `glibc_max = 2.35`（留有余量）。

image-era 格式带来两个计划级偏差，已经与所有者确认接受：

1. **首次运行下载 runtime image。** 0.16.x runtime 把解释器与 runtime 文件（`.tfs` image）拆成两个工件；当前所有已发布 Tebako 工具（含 v0.2.0）的 fat 模式只内嵌解释器，`.tfs`（约 11 MB）在首次运行时从 tamatebako 官方 Release 下载，经 SHA-256 校验后缓存于 `~/.tebako/runtimes/` 并机器级共享。完全内嵌 image 的 fat 包在上游路线图中（30c CAS），尚未发布。因此 §3.1 的「fat standalone、无任何运行时下载」期望放宽为「首次运行需要访问 github.com（或 `TEBAKO_RUNTIME_MIRROR` 指向的镜像）一次」。
2. **`--tebako-extract` 不复存在。** 新格式没有解包接口，`verify-release-tree` 随之删除；产物验证改为 `tebako inspect` 断言 `runtime_ref` 与固定的 Ruby/Tebako 版本一致（tree 边界仍由 `prepare-release-root` 在 staging 侧保证，runtime image 本身是官方按目标下载的工件）。

门禁规则：

- 顶层文件必须以 ELF magic 开头。
- ELF machine 必须与 target 一致：`AArch64` 或 `Advanced Micro Devices X86-64`。
- `ldd` 不得出现 `not found`；静态链接或 Tebako 自包含时允许明确的 `not a dynamic executable`/`statically linked` 结果。
- 顶层和内嵌 ELF 的 `GLIBC_x.y` requirement 不得高于配置中的 `glibc_max`。
- 在干净 Ubuntu 22.04 runner 上实际执行，不以静态扫描替代运行 smoke。

若 Linux Tebako 工具或产物只提供 musl 版本，应暂停 GNU 目标实现并更新兼容性决策，不能把 musl 产物命名为普通 `linux-*`。

### 3.4 私有 Release 和私有 Tap

保留当前 Release Asset API ID 下载方式：

- `feed-mob/feedmob-cli` GitHub Release 存放四个 archive 和 `SHA256SUMS`。
- `feed-mob/homebrew-tap` 存放 `Formula/fm.rb`。
- Formula 从 `HOMEBREW_GITHUB_API_TOKEN` 读取认证，仅把 header 传给 Release Asset API。
- Formula 中只保存版本、asset ID 和 SHA-256；不得保存 Token。
- Tap 仓库使用 SSH 或组织认可的 GitHub 登录方式拉取。

发布自动化优先使用组织 GitHub App 或 fine-grained token，只授予 Tap 仓库 contents/pull-request 所需权限；不使用长期个人 PAT 作为首选。

### 3.5 macOS 签名与公证独立于 Linux 发布验证

对最终 Tebako Mach-O 签名，而不是只信任 Tebako bootstrap 原有签名。顺序为：

1. press 生成最终 `fm`；
2. 执行结构、架构和 runtime-only tree 校验；
3. 对最终 `fm` 执行 Developer ID Application + hardened runtime + timestamp 签名；
4. `codesign --verify --deep --strict --verbose=2`；
5. 将签名后的文件放入临时 ZIP 提交 `notarytool`；
6. 以 `spctl --assess --type execute` 和干净机器执行作为最终验收；
7. 再从签名后的同一文件生成 Homebrew tar.gz。

不要预设裸 Mach-O 或 tar.gz 一定可以 stapling。实现阶段先验证 Apple 对当前分发容器的支持；若不能 staple，以成功 notarization、签名哈希一致和在线 Gatekeeper 验收为准，不能为了 stapling 改回已放弃的 PKG 路线。

## 4. 目标文件结构

预计修改或新增：

```text
packaging/release.yml
script/release_support.rb                 # 新增：target/config/平台公共逻辑
script/fetch-tebako-tool                  # 新增：下载固定 Tebako 工具并校验
script/verify-tebako-tool                 # 修改：--target，Mach-O/ELF 分流
script/press-release-artifact             # 修改：--target，校验原生 runner
script/verify-release-artifact            # 修改：--target，平台分流
script/verify-release-tree                # 修改：扫描 Mach-O 或 ELF
script/package-homebrew-artifact          # 新增：单 target 原生校验与归档
script/assemble-homebrew-release           # 新增：汇总四个 archive 和 checksums
script/render-homebrew-formula            # 修改：四 target Formula
script/smoke-release-auth                  # 新增：Linux 加密凭据端到端 smoke
test/release_packaging_test.rb             # 修改：公共与当前平台测试
test/release_linux_test.rb                 # 新增：Linux ELF/依赖/glibc 测试
test/release_macos_test.rb                 # 新增或拆分：Mach-O 测试
test/release_formula_test.rb               # 新增或拆分：四 target Formula 测试
.github/workflows/ci.yml                   # 修改：增加 host-specific packaging tests
.github/workflows/release.yml              # 新增：四目标构建和受保护发布
README.md                                  # 修改：macOS/Linux Homebrew 安装和支持范围
docs/2026-08-21-homebrew-macos-linux-release-plan.md
```

文件名可在实现时小幅调整，但必须保留“单目标原生构建/验证”和“四目标汇总/发布”的边界，避免在一个 Linux runner 上尝试运行 macOS 文件，或反之。

## 5. 分阶段实施

### Phase 0：基线与 Linux x86_64 可行性 spike

**目标：** 在重构整个发布链路前证明当前 CLI、Ruby 4.0.1、Tebako、Fiddle、HTTPS 和 encrypted-file store 能在 Linux x86_64 工作。

**前置：**

- [ ] PR #5 已合并到 `main`。
- [ ] 从最新 `main` 创建 `codex/linux-homebrew-release`，不要直接在 `main` 工作。
- [ ] 工作树没有非本任务的未提交改动。

**步骤：**

- [ ] 从 Tebako 官方 release 确认 Linux GNU x86_64 工具的不可变 asset 名称、版本和 SHA-256。
- [ ] 在 Ubuntu 22.04 x86_64 原生环境手工运行现有 runtime-only staging。
- [ ] 使用配置固定的 Ruby `4.0.1` 和 Tebako format/runtime line 生成 fat `fm`。
- [ ] 运行 `file`、`readelf -h`、`readelf --version-info` 和 `ldd`，记录实际 ELF machine、动态依赖和最高 glibc requirement。
- [ ] 在 `HOME` 指向临时空目录、`PATH=/usr/bin:/bin`、无 `GEM_HOME/GEM_PATH/RUBYLIB` 的环境执行：

  ```sh
  ./fm --json version
  ./fm --json doctor
  ```

- [ ] 通过 loopback fake API 完成 `auth login -> auth status -> auth logout`，验证 source 为 `encrypted_file`。
- [ ] 检查临时配置目录、key、credential、lock 文件权限和退出后状态。
- [ ] 检查 stdout/stderr 和 Actions log 不含完整测试 Token。

**退出条件：**

- [ ] Linux x86_64 standalone 能在无系统 Ruby/Gem 环境执行。
- [ ] `fiddle` native extension 架构正确且可以加载。
- [ ] HTTPS/CA 路径可用，至少能连接到公开 HTTPS endpoint 并到达 HTTP 响应层。
- [ ] encrypted-file store 端到端通过。
- [ ] 已确定 `glibc_max`，或明确记录阻塞项并停止后续 GNU 发布实现。

### Phase 1：建立统一 target 配置模型

**目标：** 消除脚本中的 `macos-#{architecture}`、固定双架构 hash 和散落的 archive 名称。

**文件：**

- 修改 `packaging/release.yml`
- 新增 `script/release_support.rb`
- 修改 `test/release_packaging_test.rb`

**建议配置结构：**

```yaml
tebako:
  release_version: "0.1.0"
  format_version: "0.15.9"
  ruby_version: "4.0.1"
  targets:
    macos-arm64:
      os: macos
      architecture: arm64
      archive: fm-darwin-arm64.tar.gz
      tebako:
        url: PINNED_OFFICIAL_ASSET_URL
        sha256: PINNED_SHA256
    macos-x86_64:
      os: macos
      architecture: x86_64
      archive: fm-darwin-x86_64.tar.gz
      tebako:
        url: PINNED_OFFICIAL_ASSET_URL
        sha256: PINNED_SHA256
    linux-arm64:
      os: linux
      architecture: arm64
      archive: fm-linux-arm64.tar.gz
      glibc_max: "2.35"
      tebako:
        url: PINNED_OFFICIAL_ASSET_URL
        sha256: PINNED_SHA256
    linux-x86_64:
      os: linux
      architecture: x86_64
      archive: fm-linux-x86_64.tar.gz
      glibc_max: "2.35"
      tebako:
        url: PINNED_OFFICIAL_ASSET_URL
        sha256: PINNED_SHA256
```

占位符只能在计划或测试 fixture 中出现；production `release.yml` 合并前必须换成官方 URL 和经过独立核对的 SHA-256。

`ReleaseSupport` 至少提供：

- `load_config(path)`：safe-load YAML 并校验 schema。
- `fetch_target(config, id)`：只允许已声明 target。
- `current_os`：规范化为 `macos`/`linux`。
- `current_architecture`：规范化为 `arm64`/`x86_64`。
- `assert_native_target!(target)`：目标与 runner 不匹配即失败。
- `compatible_macho_architectures(target)`。
- `expected_elf_machine(target)`。
- `archive_name(target)`。

**测试清单：**

- [ ] 四个合法 target 能解析。
- [ ] 未知 target、未知 OS/arch、重复 archive、非 HTTPS tool URL、非 64 位小写 SHA-256 均失败。
- [ ] `release_version`、`format_version`、`ruby_version` 缺失时失败。
- [ ] macOS target 禁止 `glibc_max`；Linux GNU target 必须声明它。
- [ ] 当前 runner 与 target 不匹配时错误中同时包含 expected/actual，但不泄露环境变量。

**验证：**

```sh
rbenv exec bundle exec ruby -Itest test/release_packaging_test.rb
rbenv exec bundle exec rubocop --format simple
```

### Phase 2：下载并验证每个平台的 Tebako 工具

**目标：** 构建 workflow 不依赖未固定的 `brew install tebako` 或 runner 缓存。

**文件：**

- 新增 `script/fetch-tebako-tool`
- 修改 `script/verify-tebako-tool`
- 补充平台测试

**接口：**

```sh
script/fetch-tebako-tool \
  --target linux-x86_64 \
  --output /tmp/tebako

script/verify-tebako-tool \
  --target linux-x86_64 \
  /tmp/tebako
```

**实现要求：**

- [ ] 下载到目标目录旁的临时文件，验证成功后原子 rename。
- [ ] 只接受配置中固定的 HTTPS URL。
- [ ] SHA-256 不匹配时删除临时文件，禁止继续执行。
- [ ] 输出只包含 target、版本、实际文件路径和非敏感校验结果。
- [ ] macOS 使用 `lipo -archs` 验证 Mach-O。
- [ ] Linux 使用 ELF magic + `readelf -h` 验证 machine。
- [ ] 校验通过后设置工具权限为 `0755`。
- [ ] 缓存 key 必须包含 target、Tebako release/format 和 SHA-256；缓存命中后仍重新校验。

**负向测试：**

- [ ] SHA 不匹配。
- [ ] macOS target 收到脚本或 ELF。
- [ ] Linux target 收到脚本或 Mach-O。
- [ ] 正确 OS、错误 CPU。
- [ ] output 已存在但 hash 不匹配。
- [ ] 下载中断不留下可执行的半成品。

### Phase 3：让 standalone 构建和校验 target-aware

**目标：** `press-release-artifact` 对四个平台使用同一接口，同时保持平台专属门禁。

**文件：**

- 修改 `script/press-release-artifact`
- 修改 `script/verify-release-artifact`
- 修改 `script/verify-release-tree`
- 修改/拆分 release packaging tests

**新接口：**

```sh
script/press-release-artifact \
  --target linux-x86_64 \
  --tebako /tmp/tebako \
  --output /tmp/fm
```

废弃 `--architecture`。不保留静默兼容；若短期需要迁移，旧参数必须输出明确 deprecation 并在同一里程碑删除。

**公共验证：**

- [ ] 调用 `assert_native_target!`，禁止正式跨平台 press。
- [ ] 先校验 Tebako 工具 hash 和平台。
- [ ] staging root 仍只包含 runtime 文件。
- [ ] Tebako 使用配置固定的 Ruby、format 和 fat mode。
- [ ] 输出目录安全创建，不覆盖已有非预期文件。
- [ ] 顶层 artifact 是普通文件、可执行、非符号链接。
- [ ] `--tebako-extract` 成功。
- [ ] 解包 tree 不包含开发依赖、测试、Git 元数据或仓库外绝对路径。
- [ ] 空 HOME/PATH 下 `fm --json version` 返回与 `FeedMob::CLI::VERSION` 一致的成功 JSON。

**macOS 专属验证：**

- [ ] 顶层 Mach-O 架构匹配 target。
- [ ] 遍历所有可识别 Mach-O，允许 arm64 target 中的 `arm64e`，拒绝错误架构。
- [ ] `fiddle` 和其他 `.bundle` 文件纳入扫描计数。
- [ ] 签名前结构验证与签名后严格验证是两个独立步骤，错误信息要区分。

**Linux 专属验证：**

- [ ] 顶层 ELF machine 匹配 target。
- [ ] 遍历所有 ELF executable/shared object，拒绝错误 machine。
- [ ] 使用 `readelf` 而不是执行任意内嵌文件来读取 header/version requirement。
- [ ] 汇总所需最高 `GLIBC_x.y` 并与 `glibc_max` 比较。
- [ ] 顶层 `ldd` 不得报告缺失库；静态文件走明确分支。
- [ ] `fiddle` 对应 `.so` 被统计并验证。

**测试设计：**

- [ ] 公共 tests 在 macOS/Linux 都运行。
- [ ] Mach-O fixtures/tests 只在 macOS runner 运行。
- [ ] ELF fixtures/tests 只在 Linux runner 运行。
- [ ] fake Tebako 使用当前 host compiler；不要让 Linux tests 依赖 `xcrun`。
- [ ] wrong-architecture 测试优先使用仓库内最小 fixture 或编译器能力；如果 runner 无法生成另一架构，测试 verifier 的解析层，不使用 QEMU 执行。
- [ ] 每个 validator 至少有 happy path、wrong format、wrong arch、missing dependency/glibc overflow 的回归覆盖。

### Phase 4：拆分单目标归档和跨目标汇总

**目标：** 解决当前 `package-homebrew-release` 必须在一台机器同时运行两个 artifact 的限制。

**文件：**

- 新增 `script/package-homebrew-artifact`
- 新增 `script/assemble-homebrew-release`
- 删除或收敛旧 `script/package-homebrew-release`
- 更新 tests

**单目标归档接口：**

```sh
script/package-homebrew-artifact \
  --target linux-x86_64 \
  --artifact /tmp/fm \
  --output /tmp/release-assets
```

行为：

- [ ] 在当前原生 runner 再次执行完整 artifact validation。
- [ ] 将同一已验证文件复制为 staging 中的 `fm` 并设置 `0755`。
- [ ] 生成 target 对应固定 archive 名称。
- [ ] archive listing 必须精确等于 `fm`，不允许 `./fm`、目录、resource fork 或额外 metadata。
- [ ] macOS 设置 `COPYFILE_DISABLE=1`。
- [ ] 同时输出 `<archive>.sha256`，供汇总 job 使用。
- [ ] output 非空时默认失败，避免混入旧版本产物。

**汇总接口：**

```sh
script/assemble-homebrew-release \
  --input /tmp/downloaded-matrix-assets \
  --output /tmp/feedmob-cli-release
```

行为：

- [ ] 必须恰好找到配置声明的四个 archive。
- [ ] 重新计算并核对每个 job 上传的 SHA-256。
- [ ] 只做 archive/list/checksum 验证，不尝试跨 OS 执行二进制。
- [ ] 生成按文件名排序、以换行结束的 `SHA256SUMS`。
- [ ] 输出 manifest JSON，供 Release 上传和 Formula 渲染使用。
- [ ] 缺失、重复、未知文件或 checksum 不一致时失败，且不生成部分 release 目录。

**Release manifest 示例：**

```json
{
  "version": "0.1.0",
  "assets": {
    "macos-arm64": {
      "name": "fm-darwin-arm64.tar.gz",
      "sha256": "..."
    }
  }
}
```

### Phase 5：Linux encrypted-file 端到端 smoke

**目标：** 验证“Linux 可以安装”同时意味着认证凭据可以安全落盘和读取，而不是只验证 `version`。

**文件：**

- 新增 `script/smoke-release-auth`
- 必要时只为可测试性调整现有 runtime injection，不改变用户接口
- 增加 smoke script tests

**测试拓扑：**

- runner 上启动只监听 `127.0.0.1` 随机端口的最小 fake HTTP server。
- 设置 `FEEDMOB_ALLOW_INSECURE_HTTP=1` 和临时 Pixel base URL。
- 使用固定非生产 sentinel Token，通过 stdin 登录。
- fake server 校验 Bearer header，但永不打印 header/token。
- 使用临时 `HOME` 和 `XDG_CONFIG_HOME`，运行安装后的 standalone。

**流程：**

```text
login --token-stdin
  -> fake GET /api/v1/cli/me = 200
status
  -> source == encrypted_file
  -> fake GET /api/v1/cli/me = 200
filesystem permission/tamper checks
logout
  -> fake DELETE /api/v1/cli/token = 2xx
status
  -> credential_missing
```

**断言：**

- [ ] stdin Token 不出现在 argv、stdout、stderr、process listing 或 test failure message。
- [ ] config directory `0700`。
- [ ] key、credential 和 lock 文件符合实现约定的 `0600`。
- [ ] credential ciphertext 不包含明文 sentinel。
- [ ] 修改 ciphertext 后 CLI 返回稳定的损坏/认证失败错误，不覆盖原文件。
- [ ] logout 后凭据不可再解析。
- [ ] 测试结束清理临时目录和 fake server。

macOS CI 不复用该 encrypted-file smoke；真实 login Keychain 的 native read/write/delete 保留为发布验收清单，避免共享 CI runner 修改用户 Keychain。

### Phase 6：生成四目标 Homebrew Formula

**目标：** 一个 Formula 在 macOS/Linux、arm64/x86_64 上选择正确的私有 Release asset。

**文件：**

- 修改 `script/render-homebrew-formula`
- 新增或拆分 `test/release_formula_test.rb`

**建议输入：**

把当前八个独立 `--*-asset-id/--*-sha256` 参数改成一个非敏感 manifest：

```sh
script/render-homebrew-formula \
  --version 0.1.0 \
  --assets-json /tmp/release-assets-with-ids.json \
  --output /tmp/homebrew-tap/Formula/fm.rb
```

manifest 中每个 target 必须包含：

- `name`
- GitHub Release `asset_id`
- `sha256`

**Formula 结构：**

```ruby
on_macos do
  on_arm do
    url MAC_ARM_API_URL, headers: download_headers
    sha256 MAC_ARM_SHA256
  end

  on_intel do
    url MAC_INTEL_API_URL, headers: download_headers
    sha256 MAC_INTEL_SHA256
  end
end

on_linux do
  on_arm do
    url LINUX_ARM_API_URL, headers: download_headers
    sha256 LINUX_ARM_SHA256
  end

  on_intel do
    url LINUX_INTEL_API_URL, headers: download_headers
    sha256 LINUX_INTEL_SHA256
  end
end
```

继续保留：

```ruby
def install
  bin.install "fm"
end

test do
  assert_match version.to_s, shell_output("#{bin}/fm --json version")
end
```

**实现要求：**

- [ ] 使用 Homebrew class-level `on_macos`/`on_linux` 和嵌套 CPU block。
- [ ] `install`/`test` 内不使用 `on_*` DSL。
- [ ] 缺少 `HOMEBREW_GITHUB_API_TOKEN` 时给出明确、无敏感值的错误说明。
- [ ] Token 只在进程环境和 HTTP Authorization header 中出现。
- [ ] version、asset ID 和 SHA-256 做严格格式验证。
- [ ] manifest 必须四 target 完整、文件名唯一、版本一致。
- [ ] renderer 只写指定 output，不直接修改或 push Tap 仓库。

**测试矩阵：**

- [ ] macOS arm64 选择正确 URL/hash。
- [ ] macOS Intel 选择正确 URL/hash。
- [ ] Linux arm64 选择正确 URL/hash。
- [ ] Linux x86_64 选择正确 URL/hash。
- [ ] 任一 asset 缺失、重复 ID、错误 hash、错误 version 都失败且不留下半成品 Formula。
- [ ] Formula Ruby syntax 通过。
- [ ] 在实际 Homebrew 环境运行 `brew style --formula`。
- [ ] 使用 `brew audit --strict --new --online`，并额外审计全部 OS/arch 条件。

### Phase 7：扩展普通 CI，但不发布

**目标：** 每个 PR 都能发现平台专属 validator 和 Formula 回归，普通 CI 不需要发布 secrets。

**文件：**

- 修改 `.github/workflows/ci.yml`

**建议 jobs：**

1. `quality`
   - Ubuntu x86_64
   - 全量 Minitest
   - RuboCop
   - gem build

2. `release-tests`
   - matrix：macOS arm64、macOS Intel、Linux arm64、Linux x86_64
   - 运行当前 host 的 release packaging tests
   - 编译当前 host 的 fake Tebako/fixture
   - 不下载真实 Tebako，不使用签名或 GitHub write token

3. `formula`
   - macOS 与 Linux 至少各一台 runner
   - 生成 fixture Formula
   - Ruby syntax、renderer tests
   - Homebrew style/audit 中不需要访问私有真实 asset 的部分

**CI 约束：**

- [ ] `permissions: contents: read` 为默认权限。
- [ ] fork/PR job 不接触 Apple 或 Tap secrets。
- [ ] matrix job 设置合理 timeout，避免 Tebako/编译挂起消耗 runner。
- [ ] 使用 Bundler cache，但 release tool cache 必须包含 SHA。
- [ ] `fail-fast: false`，一次看到全部平台结果。
- [ ] job 名称稳定，便于设为 branch protection required checks。

### Phase 8：新增受保护 Release workflow

**实施记录（2026-08-22）：** dry-run 部分已随 PR #8/#9 落地；publish 部分按以下定稿实现：

- **所有者决定不做 Apple 签名/公证**（不申请 Developer ID)，参考 googleworkspace/cli 等 CLI 的发行先例：formula 经 `brew install` 下载不携带 quarantine 属性，不触发 Gatekeeper；浏览器直接下载手动安装不是受支持路径。§3.5 与 Job C 因此移除。
- **两个仓库转为公开**（参照 cli/cli 的发行模式）:Formula 改用公开 `releases/download/v<version>/<name>` 裸 URL，不再需要 `HOMEBREW_GITHUB_API_TOKEN`、asset ID 回读合并与 download headers；`brew audit` 匿名可跑。后续仓库积累足够 notability（≥30 stars/forks/watchers）后可评估提 homebrew-core。PAT 权限随之缩小为仅 homebrew-tap 的 contents:write + pull_requests:write。
- `release` environment 限制 `main` 分支部署，publish 另要求 `confirm=release` 输入作为人工门禁。
- Job E 由 `script/publish-release` 实现（draft → 上传 → API 回读 name/size/digest → 取消 draft),Job F 在 Tap 跑 style/audit 后开 PR，不自动合并。

**目标：** 可重复地产出四平台文件；默认 dry run，只有人工批准的 publish 才改变 GitHub Release 或 Tap。

**文件：**

- 新增 `.github/workflows/release.yml`

**触发方式：**

```yaml
on:
  workflow_dispatch:
    inputs:
      version:
        required: true
      publish:
        type: boolean
        default: false
```

不要在第一版使用普通 branch push 自动发布。后续流程稳定后，可以增加 tag 触发，但仍需 protected environment approval。

**Job A — validate：**

- [ ] checkout 指定 commit。
- [ ] version 符合 semver。
- [ ] `v<version>` 与 `FeedMob::CLI::VERSION`、gemspec、release config 一致。
- [ ] Git 工作树来源 commit 已在默认分支，或显式标记 prerelease。
- [ ] 同版本 Release 不存在；禁止覆盖已发布 asset。
- [ ] 全量测试、RuboCop 和 gem build 通过。

**Job B — build matrix：**

- [ ] 根据 target 选择 runner。
- [ ] fetch + verify 固定 Tebako tool。
- [ ] press standalone。
- [ ] 平台原生 validation。
- [ ] Linux auth smoke。
- [ ] macOS 结构验证后进入签名步骤；`publish=false` 且无证书时可以产出明确标记为 unsigned 的 workflow artifact，但不能成为正式 Release asset。
- [ ] package 单 target archive。
- [ ] 上传 GitHub Actions artifact，retention 设置为有限天数。

**Job C — macOS signing/notarization：**

- [ ] 仅 `publish=true` 时运行。
- [ ] 使用 protected `release` environment。
- [ ] 创建临时 keychain，导入 Developer ID certificate，用后删除。
- [ ] secrets 使用 `::add-mask::`，脚本禁止 `set -x`。
- [ ] 最终 Mach-O 签名后重新运行架构、tree、version、codesign validation。
- [ ] notarization submission 使用独立临时 ZIP。
- [ ] 保存 `notarytool` request ID 和非敏感结果作为 provenance，不保存凭据。
- [ ] 打包的 tar.gz 必须来自签名/公证验收过的同一文件 hash。

**Job D — assemble：**

- [ ] 下载四个 matrix archive。
- [ ] 验证四目标完整性和 job checksum。
- [ ] 生成 `SHA256SUMS` 和 release manifest。
- [ ] 上传汇总 workflow artifact。
- [ ] `publish=false` 到此结束，不产生外部写入。

**Job E — publish GitHub Release：**

- [ ] 仅 `publish=true` 且受保护环境批准后执行。
- [ ] `permissions: contents: write` 只配置在该 job。
- [ ] 先创建 draft release，上传四个 archive 与 `SHA256SUMS`。
- [ ] 通过 GitHub API 回读 asset name、ID、size 和 digest，禁止依赖上传顺序。
- [ ] 将 asset ID 合并进 Formula manifest。
- [ ] 所有回读校验通过后再发布 Release；失败则保留或删除 draft，绝不留下半发布同版本。
- [ ] 已发布版本不可覆写；修复必须递增版本。

**Job F — prepare Tap PR：**

- [ ] 使用最小权限 GitHub App/fine-grained token checkout 私有 Tap。
- [ ] 从 asset-ID manifest 生成 `Formula/fm.rb`。
- [ ] 创建 `codex/fm-<version>` 分支，不直接 push Tap 的 `main`。
- [ ] 在 Tap 中运行 style、audit 和不需要跨架构执行的静态验证。
- [ ] 创建 PR，正文列出 release、四个 SHA、构建 run 和平台验收结果。
- [ ] Tap PR 需人工 review/merge；Release workflow 不自动合并。

### Phase 9：建立并验证私有 Homebrew Tap

**目标：** 用户可以在四个平台安装、升级和卸载。

**仓库：** `feed-mob/homebrew-tap`

**结构：**

```text
Formula/fm.rb
README.md
.github/workflows/test.yml
```

**Tap CI：**

- [ ] 四 target runner matrix。
- [ ] 注入只读、短生命周期的 private Release access token。
- [ ] `brew install feed-mob/tap/fm`。
- [ ] `brew test feed-mob/tap/fm`。
- [ ] `fm --json version` 与 Formula version 一致。
- [ ] `brew uninstall fm` 后 `command -v fm` 不再解析到本 Formula。
- [ ] 重新安装旧版，再更新 Formula，运行 `brew upgrade fm` 验证升级路径。
- [ ] 卸载/升级不删除 Keychain 或 encrypted-file credential；相关行为只用测试 HOME/Keychain 验证，不能触碰开发者真实凭据。

**Homebrew 检查：**

```sh
HOMEBREW_NO_INSTALL_FROM_API=1 brew install --build-from-source feed-mob/tap/fm
brew test feed-mob/tap/fm
brew audit --strict --new --online feed-mob/tap/fm
brew style --formula Formula/fm.rb
brew lgtm --online
```

虽然 Formula 下载的是预编译 archive，仍执行 Homebrew 的标准 install/test/audit/style 流程。

### Phase 10：文档、支持范围和用户体验

**文件：**

- 修改 `README.md`
- 修改 Tap `README.md`
- 可选新增 `docs/releasing.md`，在流程稳定后从本计划提炼日常 runbook

**README 必须说明：**

- [ ] 支持 macOS arm64/Intel 与 Linux GNU arm64/x86_64。
- [ ] 明确最低 macOS 和 glibc/发行版基线。
- [ ] 私有 Tap 和私有 Release 需要的 GitHub 登录方式。
- [ ] 推荐的一条安装命令、升级、卸载和故障排查。
- [ ] `HOMEBREW_GITHUB_API_TOKEN` 只需读取私有 Release，不应写入 Formula。
- [ ] macOS 使用 Keychain；Linux 使用加密本地凭据文件。
- [ ] `brew uninstall` 不删除凭据，完整退出应先运行两个服务的 auth logout。
- [ ] CI 使用环境变量凭据时的优先级和清理方法。
- [ ] Alpine/musl 和 Windows 当前不支持。

**错误体验：**

- 缺少 GitHub Token：Formula 明确提示如何配置，不输出已有 Token。
- 当前 OS/CPU 无 asset：Formula/renderer 构建阶段失败，不允许回退到错误架构。
- glibc 太旧：README 给出支持基线；CLI 无法启动时安装排障指向兼容系统，而不是让用户安装系统 Ruby。
- GitHub 403/404：区分 Tap clone 权限和 Release asset read 权限。

## 6. 测试与验收矩阵

### 6.1 自动化测试

| 能力 | macOS arm64 | macOS Intel | Linux arm64 | Linux x86_64 |
| --- | --- | --- | --- | --- |
| Ruby unit/integration | Required | Required | Required | Required |
| target config/parser | Required | Required | Required | Required |
| Tebako tool SHA/format | Mach-O | Mach-O | ELF | ELF |
| standalone top-level arch | Mach-O | Mach-O | ELF | ELF |
| embedded native files | Mach-O/.bundle | Mach-O/.bundle | ELF/.so | ELF/.so |
| no-system-Ruby version smoke | Required | Required | Required | Required |
| HTTPS/CA smoke | Required | Required | Required | Required |
| encrypted credential smoke | N/A | N/A | Required | Required |
| Homebrew install/test | Required | Required | Required | Required |
| codesign/notary | Required | Required | N/A | N/A |

### 6.2 合并前本地/CI 命令

所有 Ruby、Bundler、Rake 和 RuboCop 命令使用 rbenv：

```sh
rbenv exec bundle install
rbenv exec bundle exec rake test
rbenv exec bundle exec rubocop --format simple
rbenv exec gem build feedmob-cli.gemspec
```

平台专项：

```sh
rbenv exec bundle exec ruby -Itest test/release_packaging_test.rb
rbenv exec bundle exec ruby -Itest test/release_formula_test.rb
```

Linux runner 额外：

```sh
rbenv exec bundle exec ruby -Itest test/release_linux_test.rb
```

macOS runner 额外：

```sh
rbenv exec bundle exec ruby -Itest test/release_macos_test.rb
```

### 6.3 正式发布人工验收

每个平台使用没有本仓库、没有开发 Ruby/Gem 配置的干净用户环境：

- [ ] 安装 Homebrew。
- [ ] 配置只读 GitHub 访问。
- [ ] `brew install feed-mob/tap/fm`。
- [ ] `command -v fm` 指向 Homebrew prefix。
- [ ] `fm --json version` 版本正确。
- [ ] `fm --json doctor` 输出合法 JSON。
- [ ] 使用测试账号完成 Pixel/Time Off login/status/logout。
- [ ] 升级前一版本到当前版本。
- [ ] `brew uninstall fm` 后命令消失。
- [ ] 升级/卸载不会意外删除凭据。
- [ ] macOS Gatekeeper 不拦截，Keychain native read/write/delete 正常。
- [ ] Linux encrypted-file 权限、篡改错误和并发锁行为正常。

## 7. 安全门禁

- 所有下载的 Tebako 工具都必须固定 HTTPS URL 和 SHA-256。
- GitHub Actions 默认 `contents: read`；只有 publish job 获得 `contents: write`。
- Tap 更新永远通过 feature branch + PR，不直接 push `main`。
- Apple 证书放在 protected environment secrets，导入临时 keychain，用后清理。
- Release/Tap token 不进入命令参数、Formula、artifact、cache key 或测试快照。
- workflow 禁止 `set -x`，敏感值进入 shell 前显式 mask。
- release archive 必须来自已验证的同一 artifact hash，签名前后 hash 变化要有明确 provenance。
- GitHub Release asset 回读时按名字匹配，不按数组位置匹配。
- Formula SHA-256 必须来自最终上传 archive，不得使用 standalone 二进制 hash。
- 不覆盖已发布 tag/asset；发现问题递增 patch/prerelease 版本。
- fake auth smoke 只使用 sentinel Token 和 loopback server，不调用真实生产凭据。

## 8. 可观测性与产物留存

Release workflow summary 应列出：

- source commit SHA；
- CLI version；
- Tebako release/format/Ruby version；
- 四个 target、runner OS/arch；
- archive 文件名、大小和 SHA-256；
- Linux 最高 glibc requirement；
- macOS codesign identity 摘要和 notarization request ID；
- GitHub Release URL；
- Tap PR URL。

不得列出：

- GitHub/Apple/API Token；
- 用户凭据；
- 证书私钥或 base64 内容；
- Authorization header；
- encrypted credential key/ciphertext。

普通 dry-run artifacts 设置有限 retention。正式 Release archive 由 GitHub Release 长期保存；构建中间目录、临时 keychain、notarization ZIP 和 fake auth HOME 在 job 结束时清理。

## 9. PR 拆分建议

为了降低发布权限和跨平台重构互相影响，建议拆成三个 PR：

### PR A — Cross-platform release model

包含：

- target config 和 `ReleaseSupport`；
- Tebako tool verifier；
- Mach-O/ELF artifact/tree verifier；
- 单 target archive 与四 target assembler；
- 四目标 Formula renderer；
- 单元/平台专项 tests；
- README 中的计划性安装说明。

不包含真实 Release、签名 secrets、远端 Tap 写入。

### PR B — Build and dry-run CI

包含：

- 普通 CI 平台矩阵；
- `release.yml` 的 validate/build/assemble dry-run；
- Linux encrypted credential smoke；
- workflow artifact 和 summary。

默认 `publish=false`，没有 GitHub Release/Tap 外部写入。

### PR C — Signed publish and Tap integration

包含：

- macOS signing/notarization；
- protected release environment；
- draft/publish Release；
- asset ID 回读；
- Tap branch/PR 自动创建；
- 四平台真实 Homebrew acceptance 结果。

该 PR 和首次真实 publish 必须单独获得授权。

## 10. 回滚方案

### 构建或 CI 回归

- Revert 对应 feature PR；现有 macOS 手工脚本在 PR A 合并前保持可用。
- PR A 若替换旧参数，应在同一 PR 提供迁移后的 README，避免半套接口。

### Release 已创建但 Tap 未合并

- 保留 Release 作为可审计产物或在仍为 draft 时删除。
- 不更新 Tap，用户不会自动安装该版本。
- 修复后使用新版本，不覆盖已发布 archive。

### Tap Formula 安装失败

- 立即 revert Tap PR/commit 到上一 Formula。
- 已安装用户可执行 `brew pin fm` 或安装 Tap 中保留的上一版本 Formula；是否保留版本化 Formula 在首次发布前决定。
- GitHub Release 保留用于取证，不在原 tag 下替换文件。

### 平台单独失败

- Formula 不能悄悄把失败平台指向另一架构。
- 若必须暂时停止单个平台，发布新 Formula 明确加平台 requirement/错误说明，并开修复版本；其余平台保持上一已验证版本。

### 凭据存储回归

- 不自动删除或迁移用户凭据文件。
- 回滚 CLI 后验证旧版本仍能读取既有格式；如果格式必须演进，应先实现向后读兼容和原子迁移，再发布新版本。

## 11. 完成定义

只有同时满足以下条件，才能宣称 macOS/Linux Homebrew 发布完成：

- [ ] PR #5 已合并，Linux encrypted-file credential store 在目标 runner 通过。
- [ ] 四个平台均由原生 runner 构建，不使用模拟结果代替。
- [ ] 四个平台的结构、架构、native dependency、version smoke 全部通过。
- [ ] Linux glibc 基线已记录并在 verifier 中强制执行。
- [ ] macOS 最终 Mach-O 已签名，并通过 notarization/Gatekeeper 验收。
- [ ] GitHub Release 包含且仅包含四个 archive、`SHA256SUMS` 和预期 release notes。
- [ ] Formula 四个 OS/CPU 分支的 asset ID/hash 与 Release 回读一致。
- [ ] Homebrew style/audit/test 通过。
- [ ] 四个平台干净环境完成 install/version/auth/upgrade/uninstall 验收。
- [ ] Token、证书和 Authorization header 未出现在日志、artifact、Formula 或仓库。
- [ ] README 和 Tap README 与实际支持范围一致。
- [ ] Release run、Release URL、Tap PR 和验收结果已记录到项目 durable memory。

## 12. 实施时的第一组命令

在 PR #5 合并后，从最新默认分支开始：

```sh
git fetch origin
git switch main
git pull --ff-only origin main
git switch -c codex/linux-homebrew-release
rbenv exec bundle install
rbenv exec bundle exec rake test
rbenv exec bundle exec rubocop --format simple
```

先只执行 Phase 0 Linux x86_64 spike。Spike 达到退出条件后再进入 Phase 1，不在未证明 Tebako Linux runtime 可用时一次性修改全部发布脚本。

## 参考资料

- Tebako repository and platform support: <https://github.com/tamatebako/tebako>
- Homebrew Formula Cookbook: <https://docs.brew.sh/Formula-Cookbook>
- Homebrew Tap guide: <https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap>
- Homebrew formula validation: <https://docs.brew.sh/Adding-Software-to-Homebrew>
- GitHub-hosted runner selection: <https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job>
