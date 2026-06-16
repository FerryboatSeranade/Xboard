# Xboard Reality Machine 运维脚本

`xboard-reality-machine.sh` 用来把“新增一台 Xboard machine 模式 Reality 节点”的流程固化下来。

它适合当前这种机器形态：

- 本地 Xboard 面板跑在 Docker 容器 `xboard-web-1`。
- 远端服务器可以是已配置好的 `ssh-skill` alias，也可以只给 IP、用户名和密码。
- VLESS Reality 默认监听 `443`。
- 如果远端 `443` 被旧服务占用，可以显式传入停服命令。
- 写入面板前会自动备份 SQLite 数据库。
- 如果远端开启了 UFW/firewalld，默认会自动放行 `443/tcp`。

所有远端命令都会通过 `ssh-skill` 执行，不直接调用裸 `ssh`。

如果脚本没有执行权限，可以先运行：

```bash
chmod +x /root/data/docker_data/Xboard/ops/xboard-reality-machine.sh
```

## 先 Dry Run

建议每次新机器先跑 dry-run，看计划是否符合预期：

```bash
/root/data/docker_data/Xboard/ops/xboard-reality-machine.sh \
  --ssh-alias vultr-002 \
  --ssh-host 1.2.3.4 \
  --ssh-user root \
  --ssh-password '服务器密码' \
  --machine-name vultr-002 \
  --node-name vultr-002 \
  --yes \
  --dry-run
```

## 一条命令部署新机器

给服务器连接信息后，脚本会自动完成：

1. 创建或更新 `ssh-skill` alias。
2. 用密码首次连接远端。
3. 部署本机公钥，并把 alias 迁移成密钥免密。
4. 创建或复用 Xboard machine。
5. 创建或更新 VLESS Reality 节点。
6. 安装或更新 `xboard-node`。
7. 自动放行远端防火墙 `443/tcp`。
8. 检查公网 `443`、远端健康检查和面板在线状态。

新机器首次安装需要下载 `xboard-node` 和 `xbctl`，脚本默认给安装阶段 `900` 秒超时，避免被 `ssh-skill` 默认的短超时提前中断。

```bash
/root/data/docker_data/Xboard/ops/xboard-reality-machine.sh \
  --ssh-alias vultr-002 \
  --ssh-host 1.2.3.4 \
  --ssh-user root \
  --ssh-password '服务器密码' \
  --machine-name vultr-002 \
  --node-name vultr-002 \
  --yes
```

这里如果不单独传 `--host`，节点对外地址会默认使用 `--ssh-host`。

## 使用已有 ssh-skill alias 部署

如果远端 alias 已经存在，可以只给 alias 和节点信息：

```bash
/root/data/docker_data/Xboard/ops/xboard-reality-machine.sh \
  --ssh-alias dmit \
  --machine-name dmit \
  --node-name "dmit us" \
  --host 69.63.203.46 \
  --yes
```

默认保留已有 Reality key；只有传 `--rotate-reality-keys` 才会轮换。

## 443 被旧服务占用时

显式传入释放端口的远端命令：

```bash
/root/data/docker_data/Xboard/ops/xboard-reality-machine.sh \
  --ssh-alias dmit \
  --machine-name dmit \
  --node-name "dmit us" \
  --host 69.63.203.46 \
  --remote-stop-command "cd /root/data/docker_data/glider2 && docker compose stop glider" \
  --yes
```

这次 dmit 机器就是先停了 glider，再让 `xboard-node` 接管 `443`。

## 已安装 xboard-node，只想更新配置并重启

```bash
/root/data/docker_data/Xboard/ops/xboard-reality-machine.sh \
  --ssh-alias dmit \
  --machine-name dmit \
  --node-name "dmit us" \
  --host 69.63.203.46 \
  --skip-install \
  --yes
```

## 常用开关

- `--no-setup-ssh`：不自动创建或更新 `ssh-skill` alias。
- `--no-migrate-key-auth`：不自动部署公钥，也不迁移密钥免密。
- `--no-open-firewall`：不自动放行远端防火墙。
- `--no-public-port-check`：不检查公网端口是否可连。
- `--remote-stop-command`：目标端口被旧服务占用时，先执行这条远端命令释放端口。
- `--remote-timeout SEC`：普通远端命令超时秒数，默认 `90`。
- `--install-timeout SEC`：安装或更新 `xboard-node` 的超时秒数，默认 `900`。

## 备份位置

每次真实执行都会创建一个备份目录：

```text
/root/data/docker_data/backups/xboard-reality-machine-<UTC timestamp>/
```

常见文件：

- `database.sqlite.before`
- `database.sqlite.after`
- `ssh-probe.json`
- `ssh-deploy-pubkey.log`
- `ssh-migrate-key-auth.log`
- `panel-result.env`，包含 machine token 和 Reality 公开元信息
- `remote-before.txt`
- `remote-install.json` 或 `remote-restart.json`
- `remote-firewall.json`
- `remote-after.json`
- `public-port-check.txt`
- `panel-node-after.json`

`panel-result.env` 和远端 JSON 文件权限会设为 `600`，因为里面可能有敏感信息。

## 分支管理建议

这类脚本属于本机运维增强，不是 cedar2025/Xboard 主库代码。建议放在单独分支，例如：

```bash
git switch codex/xboard-reality-machine
```

平时同步作者代码时，让 `master` 跟 `origin/master` 保持一致；需要这些运维脚本时，再切回 `codex/xboard-reality-machine`，或者把该分支 rebase 到最新 `origin/master`。
