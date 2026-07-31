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

开发和当前的本地安装方式需要 rbenv 管理的 Ruby 3.2 或更高版本。项目的
`.ruby-version` 当前为 Ruby 4.0.1。

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

这不是 AWS CLI 那样自带 Ruby runtime 的签名 macOS 安装包。Ruby 版本的 CLI
可以采用该发布方式；后续若需要 `curl` 下载、PKG、签名/公证与自动更新，应
单独交付嵌入 Ruby 的 Tebako/PKG 发布流水线，避免把运行时与日常命令迭代耦合。

## 认证

每个服务独立保存凭据，优先级如下：

1. 对应的环境变量；
2. macOS Keychain；
3. 未配置。

| 服务 | Token 环境变量 | 默认地址 | 身份接口 | 注销行为 |
| --- | --- | --- | --- | --- |
| Pixel | `FEEDMOB_PIXEL_TOKEN` | `https://feedmob-pixel-dashboard.feedmob.com/rails` | `GET /api/v1/cli/me` | 远端撤销，并删除本地 Keychain 项 |
| Time Off | `FEEDMOB_TIME_OFF_TOKEN` | `https://time-off.feedmob.com` | `GET /api/v1/me` | 仅删除本地 Keychain 项 |

可通过 `FEEDMOB_PIXEL_BASE_URL` 和 `FEEDMOB_TIME_OFF_BASE_URL` 覆盖服务地址，
方便本地或测试环境使用。

```sh
# 默认隐藏输入；Token 不会作为命令行参数出现
fm pixel auth login
fm pixel auth status

# 仅在自动化中明确从标准输入读取
printf '%s' "$FEEDMOB_PIXEL_TOKEN" | fm pixel auth login --token-stdin

# Time Off 使用自己独立的 Token 与 API
fm time-off auth login
fm time-off auth status
```

`fm pixel auth logout` 会调用 Pixel 的 `DELETE /api/v1/cli/token` 撤销正在使用的
Token。Time Off 现有 API 没有 bearer-authenticated 的撤销端点，因此
`fm time-off auth logout` 只移除本地 Keychain 值。若当前凭据来自环境变量，CLI
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
- Keychain 写入通过 `/usr/bin/security` 的 stdin 完成，不把 Token 放进 argv；
- 日志、JSON 输出和错误信息不包含完整 Token；
- 请求仅使用 configured service host 与 bearer token；
- 当前只提供 GET 原始请求，不提供写入型 API 逃生口。
