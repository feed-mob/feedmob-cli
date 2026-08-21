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

这不是 AWS CLI 那样自带 Ruby runtime 的签名 macOS 安装包。面向非开发者的
发行方式使用下面独立的 Tebako/Homebrew 流水线，避免把运行时封装与日常命令迭代
耦合。

## macOS 发行封装

`packaging/release.yml` 固定 Tebako 下载版本和 SHA-256、Tebako runtime line
以及完整 Ruby 补丁版本。`packaging/Gemfile` 只包含运行时依赖；不要直接对仓库
根目录执行 `tebako press`，否则会把测试、开发工具和潜在 native extensions
带入产物。

先从 Tebako 官方 Release 下载与目标架构对应的工具，分别生成 standalone：

```sh
script/verify-tebako-tool \
  --architecture arm64 \
  /path/to/tebako-macos-arm64

script/press-release-artifact \
  --architecture arm64 \
  --tebako /path/to/tebako-macos-arm64 \
  --output /tmp/fm-arm64

script/press-release-artifact \
  --architecture x86_64 \
  --tebako /path/to/tebako-macos-x86_64 \
  --output /tmp/fm-x86_64
```

Intel 构建将 `arm64` 改为 `x86_64` 并使用 x86_64 Tebako 工具。正式产物必须在
对应架构的原生 runner 上构建；Apple Silicon + Rosetta 仅用于额外冒烟，不能
替代 Intel 验收。

`press-release-artifact` 会依次完成：

1. 校验 Tebako 工具的 SHA-256 和 Mach-O 架构；
2. 生成只含 `lib/`、`exe/fm` 与运行时 Gemfile/lock 的临时 root；
3. 使用固定 Ruby/runtime line 生成 fat standalone；
4. 解包并检查所有内嵌 Mach-O 架构；
5. 在无 Ruby/Gem 环境下运行 `fm --json version`。

把两个验证通过的 standalone 封装为 GitHub Release assets：

```sh
script/package-homebrew-release \
  --arm64 /tmp/fm-arm64 \
  --x86-64 /tmp/fm-x86_64 \
  --output /tmp/feedmob-cli-release
```

输出固定为 `fm-darwin-arm64.tar.gz`、`fm-darwin-x86_64.tar.gz` 和
`SHA256SUMS`。每个压缩包只包含一个可执行文件 `fm`。

仓库是私有 GitHub 仓库。上传 Release assets 后，先通过 GitHub API 取得两个
asset ID，再生成放入私有 `homebrew-tap` 仓库 `Formula/fm.rb` 的 Formula：

```sh
script/render-homebrew-formula \
  --version 0.1.0 \
  --arm64-asset-id ARM_ASSET_ID \
  --arm64-sha256 ARM_SHA256 \
  --x86-64-asset-id INTEL_ASSET_ID \
  --x86-64-sha256 INTEL_SHA256 \
  --output /path/to/homebrew-tap/Formula/fm.rb
```

Formula 使用 GitHub Release Asset API，并从用户环境读取
`HOMEBREW_GITHUB_API_TOKEN`；Token 不写入 Formula。它按 arm64/Intel 选择对应
文件并执行 `bin.install "fm"`，Homebrew 负责把命令链接到 PATH。升级或卸载
Formula 都不会删除 Keychain 凭据；需要彻底清理时，先执行对应服务的
`fm ... auth logout`。

当前 standalone 仍未签名，只能用于本地验证。正式发布时应在压缩前对 Tebako
最终 Mach-O 执行 Developer ID Application/hardened runtime 签名并完成公证；
本流水线不使用 PKG，也不需要 Developer ID Installer 证书。

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
