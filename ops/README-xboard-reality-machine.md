# Xboard Reality Machine 运维脚本

`xboard-reality-machine.sh` 用来把“新增一台 Xboard machine 模式 Reality 节点”的流程固化下来。

它适合当前这种机器形态：

- 本地 Xboard 面板跑在 Docker 容器 `xboard-web-1`。
- 远端服务器已经配置了 `ssh-skill` alias。
- VLESS Reality 默认监听 `443`。
- 如果远端 `443` 被旧服务占用，可以显式传入停服命令。
- 写入面板前会自动备份 SQLite 数据库。

所有远端命令都会通过 `ssh-skill` 执行，不直接调用裸 `ssh`。

如果脚本没有执行权限，可以先运行：

```bash
chmod +x /root/data/docker_data/Xboard/ops/xboard-reality-machine.sh
```

## 先 Dry Run

建议每次新机器先跑 dry-run，看计划是否符合预期：

```bash
/root/data/docker_data/Xboard/ops/xboard-reality-machine.sh \
  --ssh-alias dmit \
  --machine-name dmit \
  --node-name "dmit us" \
  --host 69.63.203.46 \
  --skip-install \
  --yes \
  --dry-run
```

## 新增或更新节点

```bash
/root/data/docker_data/Xboard/ops/xboard-reality-machine.sh \
  --ssh-alias dmit \
  --machine-name dmit \
  --node-name "dmit us" \
  --host 69.63.203.46 \
  --yes
```

脚本会做这些事：

1. 备份 `/root/data/docker_data/Xboard/.docker/.data/database.sqlite`。
2. 创建或复用 Xboard machine。
3. 创建或更新 VLESS Reality 节点。
4. 默认保留已有 Reality key；只有传 `--rotate-reality-keys` 才会轮换。
5. 通过 machine 模式安装器安装或更新 `xboard-node`。
6. 验证远端服务状态、健康检查、`443` 监听和面板节点在线状态。

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

## 备份位置

每次真实执行都会创建一个备份目录：

```text
/root/data/docker_data/backups/xboard-reality-machine-<UTC timestamp>/
```

常见文件：

- `database.sqlite.before`
- `database.sqlite.after`
- `panel-result.env`，包含 machine token 和 Reality 公开元信息
- `remote-before.txt`
- `remote-install.json` 或 `remote-restart.json`
- `remote-after.json`
- `panel-node-after.json`

`panel-result.env` 和远端 JSON 文件权限会设为 `600`，因为里面可能有敏感信息。

## 分支管理建议

这类脚本属于本机运维增强，不是 cedar2025/Xboard 主库代码。建议放在单独分支，例如：

```bash
git switch codex/xboard-reality-machine
```

平时同步作者代码时，让 `master` 跟 `origin/master` 保持一致；需要这些运维脚本时，再切回 `codex/xboard-reality-machine`，或者把该分支 rebase 到最新 `origin/master`。
