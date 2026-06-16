# Xboard Reality Machine 快速调用

详细说明见 `README-xboard-reality-machine.md`。这里放可以直接照着改的调用样例。

## 直接部署 vultr-003

执行时把 `服务器密码` 换成真实 root 密码即可；不要把真实密码写进 README 或提交到 git。

```bash
bash /root/data/docker_data/Xboard/ops/xboard-reality-machine.sh \
  --ssh-host 45.76.21.8 \
  --ssh-user root \
  --ssh-password '服务器密码' \
  --machine-name vultr-003 \
  --node-name vultr-003 \
  --yes
```

## 先预览计划

第一次接新机器时，可以先加 `--dry-run` 看脚本将要做什么。

```bash
bash /root/data/docker_data/Xboard/ops/xboard-reality-machine.sh \
  --ssh-host 45.76.21.8 \
  --ssh-user root \
  --ssh-password '服务器密码' \
  --machine-name vultr-003 \
  --node-name vultr-003 \
  --yes \
  --dry-run
```

## 常用提醒

- 不传 `--host` 时，节点对外地址默认使用 `--ssh-host`。
- 默认监听 Reality 推荐的 `443`。
- 同一台 VPS / 同一个 IP 建议只对应一个 machine/node；如果只是改名，复跑时保持 `--machine-name` 和 `--node-name` 一致。
- 如果远端残留旧 `xboard-node` 配置，脚本默认会先备份并清理再安装。
- 如果本机 `known_hosts` 里有旧指纹冲突，脚本默认会自动清理并重试一次。
