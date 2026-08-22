# FeedMob CLI (`fm`)

`fm` 是 FeedMob 子系统的命令行入口。第一版提供彼此隔离的 Pixel 与
Time Off 凭据、身份检查，以及只读的 API 请求能力。

```text
fm [--json] doctor
fm [--json] version
fm [--json] pixel auth login [--token-stdin]
fm [--json] pixel auth status
fm [--json] pixel auth logout
fm [--json] pixel request get <path>
fm [--json] time-off auth login [--token-stdin]
fm [--json] time-off auth status
fm [--json] time-off auth logout
fm [--json] time-off request get <path>
```

Admin 暂未纳入 CLI。

## 安装

开发和当前的本地安装方式需要 Ruby 3.2 或更高版本。项目的 `.ruby-version`
当前为 Ruby 4.0.1；本机安装时若存在 rbenv，`make install-local` 会优先使用它，
否则使用 PATH 中的 `ruby` 与 `gem`，以兼容 CI 运行环境。

```sh
rbenv exec bundle install
make install-local
export PATH="$HOME/.local/bin:$PATH"
fm version
```

`make install-local` 会构建 RubyGem，将它和依赖安装到
`~/.local/share/feedmob-cli/gems`，并在 `~/.local/bin/fm` 放置一个只使用该
独立 gem home 的启动器。因此安装后的 `fm` 可在任意工作目录运行，不依赖
本仓库的路径。可通过 `PREFIX=/your/prefix make install-local` 改变安装位置。

这不是 AWS CLI 那样自带 Ruby runtime 的签名安装包。面向非开发者的
发行方式使用下面独立的 Tebako/Homebrew 流水线，避免把运行时封装与日常命令迭代
耦合。

## macOS/Linux 发行封装

`packaging/release.yml` 固定 Tebako 下载版本和 SHA-256、Tebako runtime line
以及完整 Ruby 补丁版本。`packaging/Gemfile` 只包含运行时依赖；不要直接对仓库
根目录执行 `tebako press`，否则会把测试、开发工具和潜在 native extensions
带入产物。

支持的发布目标为 `macos-arm64`、`macos-x86_64`、`linux-arm64` 与
`linux-x86_64`。正式产物必须在对应 OS/CPU 的原生 runner 上构建和运行验证；
Rosetta/QEMU 只能作为开发辅助。首个 Linux 支持基线是 Ubuntu 22.04-compatible
GNU/glibc 系统（`glibc >= 2.35`，由 Tebako 0.1.9 官方 Linux 工具与 0.16.4
runtime 产物的 version requirement 实测决定，实际只需 `glibc >= 2.30`），
不支持 Alpine/musl。

Tebako 0.16.x 是 image-era runtime：产物内嵌解释器，但 runtime image
（约 11 MB 的 `.tfs`）在首次运行时从 tamatebako 官方 Release 下载一次，
经 SHA-256 校验后缓存于 `~/.tebako/runtimes/`（机器级共享，之后的运行不再
访问网络）。因此终端用户的首次 `fm` 运行需要能访问 github.com；可用
`TEBAKO_RUNTIME_MIRROR`（https 或 file://）指向内部镜像。

单目标构建会下载已固定 SHA-256 的 Tebako 工具、生成 standalone 包，并在原生
平台验证顶层 Mach-O/ELF 架构、Linux glibc requirement、`tebako inspect`
runtime 来源（runtime_ref 必须匹配固定的 Ruby 与 Tebako 版本）和无
Ruby/Gem 环境下的 version smoke：

```sh
script/fetch-tebako-tool \
  --target linux-x86_64 \
  --output /tmp/tebako

script/press-release-artifact \
  --target linux-x86_64 \
  --tebako /tmp/tebako \
  --output /tmp/fm

script/package-homebrew-artifact \
  --target linux-x86_64 \
  --artifact /tmp/fm \
  --output /tmp/release-linux-x86_64
```

每个单目标目录产生一个 archive 和对应 `.sha256`。四个原生 job 完成后，将其
扁平化到同一个输入目录，再执行：

```sh
script/assemble-homebrew-release \
  --input /tmp/release-input \
  --output /tmp/feedmob-cli-release
```

输出固定为四个 `fm-{darwin,linux}-{arm64,x86_64}.tar.gz`、`SHA256SUMS` 和
`release-assets.json`；每个压缩包只包含一个可执行文件 `fm`。

两个仓库都是公开的。上传 Release assets 后，用 assemble 产物的
`release-assets.json` 生成放入 `feed-mob/homebrew-tap` 的 `Formula/fm.rb`：

```sh
script/render-homebrew-formula \
  --version 0.1.0 \
  --assets-json /tmp/release-output/release-assets.json \
  --output /path/to/homebrew-tap/Formula/fm.rb
```

Formula 使用公开的 Release 下载 URL，按 OS/CPU 选择对应文件并执行
`bin.install "fm"`，无需任何 token。用户安装只需：

```sh
brew install feed-mob/tap/fm
```

升级或卸载 Formula 都不会删除 Keychain 或 Linux 加密凭据；需要彻底清理时，
先执行对应服务的 `fm ... auth logout`。

`.github/workflows/release.yml` 由 `workflow_dispatch` 手动触发。`publish=false`
（默认）是 dry-run：只构建、验证并保留 workflow artifact，绝不创建 GitHub
Release 或修改 Tap。Linux 构建还会通过
`script/smoke-release-auth` 对打包产物执行 encrypted-file 凭据的
login/status/logout 端到端验证（loopback fake API + sentinel token）。

`publish=true` 走完整发布。写操作 job 声明 `environment: release`（已限制为仅
`main` 分支可部署，secrets 只对该环境的运行可见）;org 当前套餐不支持私有仓库
的 environment reviewers，因此发布另要求 `confirm` 输入精确为 `release`，配合
validate 中仅 publish 时生效的 default-branch / 未发布版本检查作为人工门禁：

1. `publish` job 用 `script/publish-release` 创建 draft Release、上传四个
   archive 与 `SHA256SUMS`、通过 API 回读每个 asset 的 name/size/digest
   校验后才取消 draft；任何失败只保留 draft，绝不覆盖已发布版本；
2. `tap-pr` job 用 assemble 产物的 manifest 渲染 Formula，在
   `feed-mob/homebrew-tap` 跑 `brew style`/`brew audit --online` 后开
   `codex/fm-<version>` 分支 PR,人工 review 合并，workflow 不自动合并。

macOS 产物不做 Apple 签名/公证（与 googleworkspace/cli 等 CLI 的发行方式
一致）：经 `brew install` 安装的 formula 下载不携带 quarantine 属性，不会
触发 Gatekeeper；直接从浏览器下载 archive 手动安装则会被 Gatekeeper 拦截，
不作为受支持的安装路径。

发布所需的环境与 secrets（均不进入仓库）：

- GitHub environment `release`,deployment branches 限制为 `main`;
- `HOMEBREW_TAP_TOKEN`（建在 environment 级别）:fine-grained PAT，对
  `feed-mob/homebrew-tap` 有 contents:write + pull_requests:write。

正式发布不使用 PKG。

## 认证

每个服务独立保存凭据，优先级如下：

1. 对应的环境变量；
2. macOS 上的 Keychain，或其他平台上的加密本地凭据存储；
3. 未配置。

| 服务 | Token 环境变量 | 默认地址 | 身份接口 | 注销行为 |
| --- | --- | --- | --- | --- |
| Pixel | `FEEDMOB_PIXEL_TOKEN` | `https://feedmob-pixel-dashboard.feedmob.com/rails` | `GET /api/v1/cli/me` | 远端撤销，并删除本地安全存储 |
| Time Off | `FEEDMOB_TIME_OFF_TOKEN` | `https://time-off.feedmob.com` | `GET /api/v1/me` | 仅删除本地安全存储 |

可通过 `FEEDMOB_PIXEL_BASE_URL` 和 `FEEDMOB_TIME_OFF_BASE_URL` 覆盖服务地址。
覆盖地址必须使用 HTTPS，避免将 Bearer Token 明文发送到网络。仅本机回环地址
（`localhost`、`127.0.0.1` 或 `::1`）可在显式设置
`FEEDMOB_ALLOW_INSECURE_HTTP=1` 后使用 HTTP；不要在共享、测试或生产环境设置该变量。

```sh
# 默认隐藏输入；Token 不会作为命令行参数出现
fm pixel auth login
fm pixel auth status

# 仅在自动化中明确从标准输入读取
printf '%s' "$FEEDMOB_PIXEL_TOKEN" | fm pixel auth login --token-stdin

# 仅本机开发：显式允许 loopback HTTP
FEEDMOB_ALLOW_INSECURE_HTTP=1 \
  FEEDMOB_PIXEL_BASE_URL=http://127.0.0.1:3000/rails \
  fm pixel auth status

# Time Off 使用自己独立的 Token 与 API
fm time-off auth login
fm time-off auth status
```

`fm pixel auth logout` 会调用 Pixel 的 `DELETE /api/v1/cli/token` 撤销正在使用的
Token。Time Off 现有 API 没有 bearer-authenticated 的撤销端点，因此
`fm time-off auth logout` 只移除本地安全存储中的值。若当前凭据来自环境变量，CLI
无法修改父 shell；命令会指出需要 `unset` 的变量名称。

## 自动化与诊断

加上 `--json` 后，命令始终只向 stdout 输出稳定 JSON；错误也使用 JSON 信封。
`--json` 可放在命令的任意位置。

```sh
fm --json doctor
fm pixel request get /api/v1/cli/me --json
```

成功：

```json
{"ok":true,"data":{"service":"pixel","authenticated":true}}
```

失败：

```json
{"ok":false,"error":{"code":"credential_missing","message":"No Pixel credential is configured."}}
```

`doctor` 即使没有配置 Token 也会成功完成，并逐项展示需要配置的服务；已配置的
服务会调用其身份接口验证当前凭据。`request get` 仅允许以单个 `/` 开头的相对
路径，拒绝绝对 URL 与 `//host` 路径，避免 Token 被转发到配置之外的主机。

常见的非零退出情形包括缺少凭据、无效 Token、网络故障、非 2xx API 响应和无效
请求路径。

## 安全边界

- CLI 不提供 `--token`，避免 Token 进入 shell history 或进程参数；
- macOS 直接经 Security.framework 读写 Keychain，Token 不经过子进程的 argv 或 stdout；
- 非 macOS 使用 AES-256-GCM 加密本地凭据；Unix 上目录为 `0700`、密钥/密文/锁文件为
  `0600`，并使用文件锁和原子替换。它是系统 Keychain 不可用时的后备，不应用于共享用户帐户；
- 日志、JSON 输出和错误信息不包含完整 Token；
- 请求仅使用 configured service host、HTTPS 与 bearer token；仅显式 opt-in 的 loopback HTTP
  可作为本机开发例外；
- 当前只提供 GET 原始请求，不提供写入型 API 逃生口。
