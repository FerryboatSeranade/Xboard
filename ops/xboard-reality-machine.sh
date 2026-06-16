#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_XBOARD_DIR="/root/data/docker_data/Xboard"
DEFAULT_CONTAINER="xboard-web-1"
DEFAULT_PANEL_URL=""
DEFAULT_GROUPS="1"
DEFAULT_PORT="443"
DEFAULT_HEALTH_PORT="65530"
DEFAULT_REMOTE_TIMEOUT="90"
DEFAULT_INSTALL_TIMEOUT="900"
DEFAULT_REALITY_SNI="addons.mozilla.org"
DEFAULT_REALITY_DEST_PORT="443"
DEFAULT_FINGERPRINT="chrome"
DEFAULT_FLOW="xtls-rprx-vision"
DEFAULT_RATE="1"

xboard_dir="$DEFAULT_XBOARD_DIR"
container="$DEFAULT_CONTAINER"
panel_url="$DEFAULT_PANEL_URL"
groups="$DEFAULT_GROUPS"
port="$DEFAULT_PORT"
health_port="$DEFAULT_HEALTH_PORT"
remote_timeout="$DEFAULT_REMOTE_TIMEOUT"
install_timeout="$DEFAULT_INSTALL_TIMEOUT"
reality_sni="$DEFAULT_REALITY_SNI"
reality_dest_port="$DEFAULT_REALITY_DEST_PORT"
fingerprint="$DEFAULT_FINGERPRINT"
flow="$DEFAULT_FLOW"
rate="$DEFAULT_RATE"
ssh_alias=""
ssh_host=""
ssh_user="root"
ssh_port="22"
ssh_password=""
ssh_key_file="$HOME/.ssh/id_ed25519"
machine_name=""
node_name=""
host=""
remote_stop_command=""
show="true"
enabled="true"
skip_install="false"
rotate_reality_keys="false"
migrate_key_auth="true"
auto_install_local_deps="true"
auto_fix_known_hosts="true"
open_firewall="true"
verify_public_port="true"
assume_yes="false"
dry_run="false"
remote_auth_mode="key"
ssh_key_file_explicit="false"

usage() {
  cat <<'EOF'
用法:
  ops/xboard-reality-machine.sh [选项]

用途:
  为 Xboard 创建或更新 machine 模式的 VLESS Reality 节点，
  通过原生 OpenSSH 在远端安装或重启 xboard-node，并验证 443 端口。

常用示例:
  ops/xboard-reality-machine.sh
  ops/xboard-reality-machine.sh --ssh-host 1.2.3.4 --ssh-user root --ssh-password '密码' --machine-name vultr-002 --node-name vultr-002 --yes
  ops/xboard-reality-machine.sh --ssh-host dmit --machine-name dmit --node-name "dmit us" --host 69.63.203.46 --yes

选项:
  --xboard-dir DIR             Xboard 目录。默认: /root/data/docker_data/Xboard
  --container NAME             Xboard PHP 容器名。默认: xboard-web-1
  --panel-url URL              面板 URL。留空时自动检测
  --ssh-alias ALIAS            本地标签；可作为 machine/node 默认名称，不依赖 ssh-skill
  --ssh-host HOST              远端 SSH 主机名、IP 或 OpenSSH Host alias
  --ssh-user USER              远端 SSH 用户。默认: root
  --ssh-port PORT              远端 SSH 端口。默认: 22
  --ssh-password PASSWORD      远端 SSH 密码；用于首次连通和部署公钥
  --ssh-key-file PATH          迁移免密使用的本机私钥。默认: ~/.ssh/id_ed25519
  --machine-name NAME          Xboard machine 名称；同名会复用
  --node-name NAME             Xboard 节点名称；同名 VLESS 节点会更新
  --host HOST                  客户端看到的节点主机名或 IP
  --groups CSV                 用户组 ID，逗号分隔。默认: 1
  --port PORT                  客户端连接端口/服务监听端口。默认: 443
  --health-port PORT           xboard-node 健康检查端口。默认: 65530
  --remote-timeout SEC         普通远端命令超时秒数。默认: 90
  --install-timeout SEC        xboard-node 安装/更新超时秒数。默认: 900
  --reality-sni HOST           Reality 伪装目标 SNI。默认: addons.mozilla.org
  --reality-dest-port PORT     Reality 伪装目标端口。默认: 443
  --fingerprint NAME           uTLS 指纹。默认: chrome
  --flow NAME                  VLESS flow。默认: xtls-rprx-vision
  --rate RATE                  节点倍率。默认: 1
  --show true|false            是否展示给用户。默认: true
  --enabled true|false         是否启用 machine 同步。默认: true
  --remote-stop-command CMD    当目标端口被占用时，用于释放端口的远端命令
                               示例: "cd /root/data/docker_data/glider2 && docker compose stop glider"
  --skip-install               不运行安装器，只重启/验证已有 xboard-node
  --rotate-reality-keys        更新已有节点时也轮换 Reality key
  --no-install-local-deps       不自动安装本机 sshpass 等依赖
  --no-fix-known-hosts         不自动清理本机 known_hosts 里的旧主机指纹
  --no-migrate-key-auth        不自动部署公钥/迁移密钥认证
  --no-open-firewall           不自动放行远端防火墙 443/tcp
  --no-public-port-check       不从本机检查节点公网端口
  --yes                        非交互模式，接受默认确认
  --dry-run                    只打印计划，不改本地或远端状态
  -h, --help                   显示帮助

说明:
  远端命令使用本机 ssh/sshpass 执行，不依赖 ssh-skill 或 Codex 环境。

  写入面板前会备份 SQLite 数据库:
    /root/data/docker_data/backups/xboard-reality-machine-<timestamp>/
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

warn() {
  echo "WARN: $*" >&2
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

shell_quote() {
  local value="${1-}"
  printf "'%s'" "$(printf "%s" "$value" | sed "s/'/'\\\\''/g")"
}

expand_path() {
  local value="${1-}"
  if [[ "$value" == "~/"* ]]; then
    printf "%s/%s" "$HOME" "${value#~/}"
  else
    printf "%s" "$value"
  fi
}

prompt() {
  local var_name="$1"
  local label="$2"
  local default_value="${3-}"
  local value=""

  if is_true "$assume_yes"; then
    printf -v "$var_name" "%s" "$default_value"
    return
  fi

  if [[ -n "$default_value" ]]; then
    read -r -p "$label [$default_value]: " value
    value="${value:-$default_value}"
  else
    read -r -p "$label: " value
  fi
  printf -v "$var_name" "%s" "$value"
}

confirm() {
  local label="$1"
  local default="${2:-n}"
  local answer=""

  if is_true "$assume_yes"; then
    [[ "$default" == "y" ]]
    return
  fi

  if [[ "$default" == "y" ]]; then
    read -r -p "$label [Y/n]: " answer
    answer="${answer:-Y}"
  else
    read -r -p "$label [y/N]: " answer
    answer="${answer:-N}"
  fi

  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --xboard-dir) xboard_dir="${2:?}"; shift 2 ;;
      --container) container="${2:?}"; shift 2 ;;
      --panel-url) panel_url="${2:?}"; shift 2 ;;
      --ssh-alias) ssh_alias="${2:?}"; shift 2 ;;
      --ssh-host) ssh_host="${2:?}"; shift 2 ;;
      --ssh-user) ssh_user="${2:?}"; shift 2 ;;
      --ssh-port) ssh_port="${2:?}"; shift 2 ;;
      --ssh-password) ssh_password="${2:?}"; shift 2 ;;
      --ssh-key-file) ssh_key_file="${2:?}"; ssh_key_file_explicit="true"; shift 2 ;;
      --machine-name) machine_name="${2:?}"; shift 2 ;;
      --node-name) node_name="${2:?}"; shift 2 ;;
      --host) host="${2:?}"; shift 2 ;;
      --groups) groups="${2:?}"; shift 2 ;;
      --port) port="${2:?}"; shift 2 ;;
      --health-port) health_port="${2:?}"; shift 2 ;;
      --remote-timeout) remote_timeout="${2:?}"; shift 2 ;;
      --install-timeout) install_timeout="${2:?}"; shift 2 ;;
      --reality-sni) reality_sni="${2:?}"; shift 2 ;;
      --reality-dest-port) reality_dest_port="${2:?}"; shift 2 ;;
      --fingerprint) fingerprint="${2:?}"; shift 2 ;;
      --flow) flow="${2:?}"; shift 2 ;;
      --rate) rate="${2:?}"; shift 2 ;;
      --show) show="${2:?}"; shift 2 ;;
      --enabled) enabled="${2:?}"; shift 2 ;;
      --remote-stop-command) remote_stop_command="${2:?}"; shift 2 ;;
      --skip-install) skip_install="true"; shift ;;
      --rotate-reality-keys) rotate_reality_keys="true"; shift ;;
      --no-install-local-deps) auto_install_local_deps="false"; shift ;;
      --no-setup-ssh) auto_install_local_deps="false"; shift ;;
      --no-fix-known-hosts) auto_fix_known_hosts="false"; shift ;;
      --no-migrate-key-auth) migrate_key_auth="false"; shift ;;
      --no-open-firewall) open_firewall="false"; shift ;;
      --no-public-port-check) verify_public_port="false"; shift ;;
      --yes) assume_yes="true"; shift ;;
      --dry-run) dry_run="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
}

require_local_tools() {
  command -v docker >/dev/null || die "docker is required"
  command -v python3 >/dev/null || die "python3 is required"
  docker ps --format '{{.Names}}' | grep -Fxq "$container" || die "container not running: $container"
  [[ -d "$xboard_dir" ]] || die "Xboard directory not found: $xboard_dir"
}

detect_panel_url() {
  if [[ -n "$panel_url" ]]; then
    return
  fi

  local detected=""
  detected="$(docker exec "$container" php artisan tinker --execute='echo rtrim((string) (admin_setting("app_url") ?: config("app.url")), "/");' 2>/dev/null || true)"
  if [[ -n "$detected" && "$detected" != "http://localhost" ]]; then
    panel_url="$detected"
  fi
}

collect_inputs() {
  detect_panel_url

  if [[ -z "$ssh_host" ]]; then
    prompt ssh_host "SSH host/IP or OpenSSH alias"
  fi
  if [[ -z "$ssh_host" && -n "$host" ]]; then
    ssh_host="$host"
  fi
  if [[ -n "$ssh_host" && -z "$host" ]]; then
    host="$ssh_host"
  fi
  if [[ -z "$host" ]]; then
    prompt host "Node host/IP shown to clients"
  fi
  if [[ -z "$ssh_alias" ]]; then
    ssh_alias="$ssh_host"
  fi
  if [[ -z "$machine_name" ]]; then
    prompt machine_name "Xboard machine name" "$ssh_alias"
  fi
  if [[ -z "$node_name" ]]; then
    prompt node_name "Xboard node name" "$machine_name"
  fi
  if [[ -z "$panel_url" ]]; then
    prompt panel_url "Panel URL" "https://xb.998585.xyz"
  fi

  prompt groups "Group IDs, comma separated" "$groups"
  prompt port "Reality listen/client port" "$port"
  prompt health_port "xboard-node health port" "$health_port"
  prompt reality_sni "Reality destination SNI" "$reality_sni"
  prompt reality_dest_port "Reality destination port" "$reality_dest_port"

  [[ -n "$ssh_host" ]] || die "--ssh-host is required"
  [[ -n "$host" ]] || die "--host is required"
  [[ "$ssh_port" =~ ^[0-9]+$ ]] || die "--ssh-port must be numeric"
  [[ -n "$machine_name" ]] || die "--machine-name is required"
  [[ -n "$node_name" ]] || die "--node-name is required"
  [[ "$port" =~ ^[0-9]+$ ]] || die "--port must be numeric"
  [[ "$health_port" =~ ^[0-9]+$ ]] || die "--health-port must be numeric"
  [[ "$remote_timeout" =~ ^[0-9]+$ ]] || die "--remote-timeout must be numeric"
  [[ "$install_timeout" =~ ^[0-9]+$ ]] || die "--install-timeout must be numeric"
  [[ "$reality_dest_port" =~ ^[0-9]+$ ]] || die "--reality-dest-port must be numeric"
}

preview() {
  cat <<EOF

Plan
  Xboard dir:        $xboard_dir
  Container:         $container
  Panel URL:         $panel_url
  SSH label:         $ssh_alias
  SSH target:        $ssh_user@$ssh_host:$ssh_port
  Machine:           $machine_name
  Node:              $node_name
  Host:              $host
  Groups:            $groups
  Listen port:       $port
  Health port:       $health_port
  Remote timeout:    ${remote_timeout}s
  Install timeout:   ${install_timeout}s
  Reality dest:      $reality_sni:$reality_dest_port
  Fingerprint/flow:  $fingerprint / $flow
  Show/enabled:      $show / $enabled
  Skip install:      $skip_install
  Rotate keys:       $rotate_reality_keys
  Install deps:      $auto_install_local_deps
  Fix known_hosts:   $auto_fix_known_hosts
  Migrate key auth:  $migrate_key_auth
  Open firewall:     $open_firewall
  Public port check: $verify_public_port
  Dry run:           $dry_run
EOF
}

make_backup_dir() {
  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_dir="/root/data/docker_data/backups/xboard-reality-machine-$ts"
  if ! is_true "$dry_run"; then
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"
  fi
}

backup_database() {
  local sqlite_path="$xboard_dir/.docker/.data/database.sqlite"
  if [[ ! -f "$sqlite_path" ]]; then
    warn "SQLite database not found at $sqlite_path; skipping file backup"
    return
  fi

  info "Backing up SQLite database"
  if is_true "$dry_run"; then
    echo "DRY-RUN: cp -a $sqlite_path $backup_dir/database.sqlite.before"
    return
  fi
  cp -a "$sqlite_path" "$backup_dir/database.sqlite.before"
}

panel_upsert() {
  info "Creating/updating Xboard machine and VLESS Reality node"

  if is_true "$dry_run"; then
    echo "DRY-RUN: would upsert machine '$machine_name' and node '$node_name' in $container"
    machine_id="DRY_RUN_MACHINE_ID"
    machine_token="DRY_RUN_MACHINE_TOKEN"
    node_id="DRY_RUN_NODE_ID"
    node_action="dry-run"
    return
  fi

  local php_code result_file
  result_file="$backup_dir/panel-result.env"
  php_code="$(cat <<'PHP'
$bool = function ($value): bool {
    return in_array(strtolower((string) $value), ['1', 'true', 'yes', 'y'], true);
};
$base64Url = function (string $bytes): string {
    return rtrim(strtr(base64_encode($bytes), '+/', '-_'), '=');
};
$generateReality = function () use ($base64Url): array {
    $private = random_bytes(SODIUM_CRYPTO_SCALARMULT_SCALARBYTES);
    $public = sodium_crypto_scalarmult_base($private);
    return [
        'private_key' => $base64Url($private),
        'public_key' => $base64Url($public),
        'short_id' => bin2hex(random_bytes(8)),
    ];
};

$machineName = getenv('XBR_MACHINE_NAME');
$nodeName = getenv('XBR_NODE_NAME');
$host = getenv('XBR_HOST');
$groups = array_values(array_filter(array_map('trim', explode(',', getenv('XBR_GROUPS') ?: '1')), fn ($v) => $v !== ''));
$groups = array_map('strval', $groups);
$port = (int) getenv('XBR_PORT');
$realitySni = getenv('XBR_REALITY_SNI') ?: 'addons.mozilla.org';
$realityDestPort = (string) (getenv('XBR_REALITY_DEST_PORT') ?: '443');
$fingerprint = getenv('XBR_FINGERPRINT') ?: 'chrome';
$flow = getenv('XBR_FLOW') ?: 'xtls-rprx-vision';
$rate = (string) (getenv('XBR_RATE') ?: '1');
$show = $bool(getenv('XBR_SHOW') ?: 'true');
$enabled = $bool(getenv('XBR_ENABLED') ?: 'true');
$rotateKeys = $bool(getenv('XBR_ROTATE_REALITY_KEYS') ?: 'false');

if (!$machineName || !$nodeName || !$host || !$port) {
    throw new RuntimeException('missing required environment values');
}

$machine = \App\Models\ServerMachine::where('name', $machineName)->first();
$machineAction = 'reused';
if (!$machine) {
    $machine = \App\Models\ServerMachine::create([
        'name' => $machineName,
        'notes' => "created by ops/xboard-reality-machine.sh for {$host}",
        'is_active' => true,
        'token' => \App\Models\ServerMachine::generateToken(),
    ]);
    $machineAction = 'created';
} elseif (!$machine->is_active) {
    $machine->is_active = true;
    $machine->save();
}

$server = \App\Models\Server::where('name', $nodeName)->where('type', \App\Models\Server::TYPE_VLESS)->first();
$nodeAction = $server ? 'updated' : 'created';
$settings = $server?->protocol_settings ?: [];
$existingReality = $settings['reality_settings'] ?? [];

if (
    $rotateKeys
    || empty($existingReality['private_key'])
    || empty($existingReality['public_key'])
    || empty($existingReality['short_id'])
) {
    $keys = $generateReality();
    $keyAction = $rotateKeys ? 'rotated' : 'generated';
} else {
    $keys = [
        'private_key' => $existingReality['private_key'],
        'public_key' => $existingReality['public_key'],
        'short_id' => $existingReality['short_id'],
    ];
    $keyAction = 'kept';
}

$protocolSettings = [
    'tls' => 2,
    'tls_settings' => [
        'server_name' => null,
        'allow_insecure' => false,
        'ech' => null,
    ],
    'flow' => $flow,
    'encryption' => null,
    'network' => 'tcp',
    'network_settings' => null,
    'reality_settings' => [
        'server_name' => $realitySni,
        'server_port' => $realityDestPort,
        'public_key' => $keys['public_key'],
        'private_key' => $keys['private_key'],
        'short_id' => $keys['short_id'],
        'allow_insecure' => false,
    ],
    'multiplex' => [
        'enabled' => false,
        'protocol' => 'yamux',
        'max_connections' => null,
        'padding' => false,
        'brutal' => [
            'enabled' => false,
            'up_mbps' => null,
            'down_mbps' => null,
        ],
    ],
    'utls' => [
        'enabled' => true,
        'fingerprint' => $fingerprint,
    ],
];

$payload = [
    'type' => \App\Models\Server::TYPE_VLESS,
    'code' => $server?->code,
    'parent_id' => null,
    'machine_id' => $machine->id,
    'group_ids' => $groups,
    'route_ids' => [],
    'name' => $nodeName,
    'rate' => $rate,
    'tags' => [],
    'host' => $host,
    'port' => (string) $port,
    'server_port' => $port,
    'protocol_settings' => $protocolSettings,
    'show' => $show,
    'enabled' => $enabled,
];

if ($server) {
    $server->fill($payload);
    $server->save();
} else {
    $payload['sort'] = ((int) (\App\Models\Server::max('sort') ?: 0)) + 10;
    $server = \App\Models\Server::create($payload);
}

\App\Services\NodeSyncService::notifyMachineNodesChanged($machine->id);

echo 'MACHINE_ACTION=' . $machineAction . PHP_EOL;
echo 'MACHINE_ID=' . $machine->id . PHP_EOL;
echo 'MACHINE_TOKEN=' . $machine->token . PHP_EOL;
echo 'NODE_ACTION=' . $nodeAction . PHP_EOL;
echo 'NODE_ID=' . $server->id . PHP_EOL;
echo 'NODE_NAME=' . $server->name . PHP_EOL;
echo 'NODE_HOST=' . $server->host . PHP_EOL;
echo 'NODE_PORT=' . $server->port . PHP_EOL;
echo 'KEY_ACTION=' . $keyAction . PHP_EOL;
echo 'PUBLIC_KEY=' . $keys['public_key'] . PHP_EOL;
echo 'SHORT_ID=' . $keys['short_id'] . PHP_EOL;
PHP
)"

  docker exec \
    -e XBR_MACHINE_NAME="$machine_name" \
    -e XBR_NODE_NAME="$node_name" \
    -e XBR_HOST="$host" \
    -e XBR_GROUPS="$groups" \
    -e XBR_PORT="$port" \
    -e XBR_REALITY_SNI="$reality_sni" \
    -e XBR_REALITY_DEST_PORT="$reality_dest_port" \
    -e XBR_FINGERPRINT="$fingerprint" \
    -e XBR_FLOW="$flow" \
    -e XBR_RATE="$rate" \
    -e XBR_SHOW="$show" \
    -e XBR_ENABLED="$enabled" \
    -e XBR_ROTATE_REALITY_KEYS="$rotate_reality_keys" \
    "$container" php artisan tinker --execute="$php_code" > "$result_file"
  chmod 600 "$result_file"

  machine_id="$(awk -F= '$1=="MACHINE_ID"{print $2}' "$result_file")"
  machine_token="$(awk -F= '$1=="MACHINE_TOKEN"{print $2}' "$result_file")"
  node_id="$(awk -F= '$1=="NODE_ID"{print $2}' "$result_file")"
  node_action="$(awk -F= '$1=="NODE_ACTION"{print $2}' "$result_file")"

  [[ -n "$machine_id" && -n "$machine_token" && -n "$node_id" ]] || die "failed to parse panel result"
  awk -F= '
    $1=="MACHINE_ACTION" { print "MACHINE_ACTION=" $2 }
    $1=="MACHINE_ID" { print "MACHINE_ID=" $2 }
    $1=="NODE_ACTION" { print "NODE_ACTION=" $2 }
    $1=="NODE_ID" { print "NODE_ID=" $2 }
    $1=="NODE_NAME" { print "NODE_NAME=" $2 }
    $1=="NODE_HOST" { print "NODE_HOST=" $2 }
    $1=="NODE_PORT" { print "NODE_PORT=" $2 }
    $1=="KEY_ACTION" { print "KEY_ACTION=" $2 }
  ' "$result_file"
}

backup_database_after() {
  local sqlite_path="$xboard_dir/.docker/.data/database.sqlite"
  [[ -f "$sqlite_path" ]] || return
  if ! is_true "$dry_run"; then
    cp -a "$sqlite_path" "$backup_dir/database.sqlite.after"
  fi
}

install_local_package() {
  local package="$1"

  [[ "$auto_install_local_deps" == "true" ]] || die "$package is required; install it or remove --no-install-local-deps"
  [[ "$(id -u)" == "0" ]] || die "$package is required; run as root or install it manually"

  info "Installing local dependency: $package"
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "$package"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$package"
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache "$package"
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm "$package"
  else
    die "cannot install $package automatically; install it manually"
  fi
}

ensure_local_ssh_tools() {
  command -v ssh >/dev/null || die "ssh is required"
  command -v ssh-keygen >/dev/null || die "ssh-keygen is required"
  command -v timeout >/dev/null || die "timeout is required"

  if [[ -n "$ssh_password" ]] && ! command -v sshpass >/dev/null 2>&1; then
    if is_true "$dry_run"; then
      echo "DRY-RUN: would install sshpass for password SSH"
    else
      install_local_package sshpass
    fi
  fi
}

ensure_local_ssh_key() {
  local expanded_key
  expanded_key="$(expand_path "$ssh_key_file")"

  if [[ -f "$expanded_key" && -f "${expanded_key}.pub" ]]; then
    return
  fi

  if is_true "$dry_run"; then
    echo "DRY-RUN: would generate SSH key $expanded_key"
    return
  fi

  mkdir -p "$(dirname "$expanded_key")"
  chmod 700 "$(dirname "$expanded_key")" || true
  info "Generating local SSH key: $expanded_key"
  ssh-keygen -t ed25519 -f "$expanded_key" -N "" -C "xboard-reality-machine@$(hostname 2>/dev/null || echo local)"
}

remote_target() {
  printf "%s@%s" "$ssh_user" "$ssh_host"
}

remote_exec() {
  local timeout_seconds="$1"
  local remote_cmd="$2"
  local target
  local expanded_key
  local -a ssh_args

  target="$(remote_target)"
  expanded_key="$(expand_path "$ssh_key_file")"
  ssh_args=(
    -p "$ssh_port"
    -o "StrictHostKeyChecking=accept-new"
    -o "ConnectTimeout=15"
    -o "ServerAliveInterval=30"
    -o "ServerAliveCountMax=3"
  )

  if [[ "$remote_auth_mode" == "password" ]]; then
    [[ -n "$ssh_password" ]] || die "--ssh-password is required for password auth"
    command -v sshpass >/dev/null || die "sshpass is required for password auth"
    SSHPASS="$ssh_password" timeout "$timeout_seconds" sshpass -e ssh \
      "${ssh_args[@]}" \
      -o "PreferredAuthentications=password" \
      -o "PubkeyAuthentication=no" \
      "$target" "$remote_cmd"
  else
    if [[ "$ssh_key_file_explicit" == "true" && ! -f "$expanded_key" ]]; then
      die "SSH key file not found: $expanded_key"
    fi
    if [[ -f "$expanded_key" && ( "$ssh_key_file_explicit" == "true" || -n "$ssh_password" ) ]]; then
      ssh_args+=(-i "$expanded_key")
    fi
    timeout "$timeout_seconds" ssh "${ssh_args[@]}" "$target" "$remote_cmd"
  fi
}

is_known_hosts_mismatch() {
  local stderr_file="$1"
  grep -Eq 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed|Offending .* key in .*known_hosts' "$stderr_file"
}

fix_known_hosts_for_remote() {
  local known_host="$ssh_host"

  [[ "$auto_fix_known_hosts" == "true" ]] || return 1
  [[ -n "$known_host" ]] || return 1
  command -v ssh-keygen >/dev/null || return 1

  info "Removing stale known_hosts entry for $known_host"
  ssh-keygen -R "$known_host" >/dev/null 2>&1 || true
  if [[ "$ssh_port" != "22" ]]; then
    ssh-keygen -R "[$known_host]:$ssh_port" >/dev/null 2>&1 || true
  fi
}

write_remote_result_json() {
  local exit_code="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local result_file="$4"

  python3 - "$exit_code" "$stdout_file" "$stderr_file" <<'PY' > "$result_file"
import json
import sys
from pathlib import Path

exit_code = int(sys.argv[1])
stdout = Path(sys.argv[2]).read_text(errors="replace")
stderr = Path(sys.argv[3]).read_text(errors="replace")
print(json.dumps({
    "success": exit_code == 0,
    "exit_code": exit_code,
    "stdout": stdout,
    "stderr": stderr,
}, ensure_ascii=False, indent=2))
PY
  chmod 600 "$result_file" || true
}

remote_run_capture() {
  local remote_cmd="$1"
  local result_file="${2:-}"
  local timeout_seconds="${3:-$remote_timeout}"
  local stdout_file stderr_file status

  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  set +e
  remote_exec "$timeout_seconds" "$remote_cmd" >"$stdout_file" 2>"$stderr_file"
  status=$?
  if [[ "$status" -ne 0 ]] && is_known_hosts_mismatch "$stderr_file" && fix_known_hosts_for_remote; then
    : >"$stdout_file"
    : >"$stderr_file"
    remote_exec "$timeout_seconds" "$remote_cmd" >"$stdout_file" 2>"$stderr_file"
    status=$?
  fi
  set -e

  cat "$stdout_file"
  cat "$stderr_file" >&2

  if [[ -n "$result_file" ]]; then
    write_remote_result_json "$status" "$stdout_file" "$stderr_file" "$result_file"
  fi

  rm -f "$stdout_file" "$stderr_file"
  return "$status"
}

remote_run() {
  local name="$1"
  local remote_cmd="$2"
  local result_file="${3:-}"
  local timeout_seconds="${4:-$remote_timeout}"

  info "$name"
  if is_true "$dry_run"; then
    echo "DRY-RUN remote[$ssh_user@$ssh_host:$ssh_port]: $remote_cmd"
    return
  fi

  remote_run_capture "$remote_cmd" "$result_file" "$timeout_seconds"
}

remote_run_allow_fail() {
  remote_run "$@"
}

remote_stdout() {
  local remote_cmd="$1"
  local timeout_seconds="${2:-$remote_timeout}"
  local stdout_file stderr_file status

  if is_true "$dry_run"; then
    echo "DRY-RUN remote[$ssh_user@$ssh_host:$ssh_port]: $remote_cmd"
    return
  fi

  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"
  set +e
  remote_exec "$timeout_seconds" "$remote_cmd" >"$stdout_file" 2>"$stderr_file"
  status=$?
  if [[ "$status" -ne 0 ]] && is_known_hosts_mismatch "$stderr_file" && fix_known_hosts_for_remote; then
    : >"$stdout_file"
    : >"$stderr_file"
    remote_exec "$timeout_seconds" "$remote_cmd" >"$stdout_file" 2>"$stderr_file"
    status=$?
  fi
  set -e

  if [[ "$status" -ne 0 ]]; then
    cat "$stderr_file" >&2
    rm -f "$stdout_file" "$stderr_file"
    return "$status"
  fi

  cat "$stdout_file"
  rm -f "$stdout_file" "$stderr_file"
}

deploy_public_key_to_remote() {
  local expanded_key pubkey_file pubkey deploy_cmd

  expanded_key="$(expand_path "$ssh_key_file")"
  pubkey_file="${expanded_key}.pub"
  [[ -f "$pubkey_file" ]] || die "public key not found: $pubkey_file"

  pubkey="$(cat "$pubkey_file")"
  deploy_cmd="set -e; umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF $(shell_quote "$pubkey") ~/.ssh/authorized_keys || printf '%s\n' $(shell_quote "$pubkey") >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
  remote_run "Deploying local public key" "$deploy_cmd" "$backup_dir/ssh-deploy-pubkey.json" "$remote_timeout"
}

bootstrap_remote_ssh() {
  local probe_cmd
  probe_cmd='set -e; echo "whoami=$(whoami)"; echo "hostname=$(hostname)"; echo "ssh_connection=$SSH_CONNECTION"; echo "local_ips=$(hostname -I 2>/dev/null || true)"; echo "public_v4=$(curl -4 -fsS --max-time 8 https://api.ipify.org || true)"; echo "machine_id=$(cat /etc/machine-id 2>/dev/null || true)"'

  ensure_local_ssh_tools
  if [[ "$migrate_key_auth" == "true" && -n "$ssh_password" ]]; then
    ensure_local_ssh_key
  fi

  if [[ -n "$ssh_password" ]]; then
    remote_auth_mode="password"
  else
    remote_auth_mode="key"
  fi

  remote_run "Verifying SSH connection" "$probe_cmd" "$backup_dir/ssh-probe.json" "$remote_timeout"

  if [[ "$migrate_key_auth" == "false" ]]; then
    return
  fi

  if [[ -n "$ssh_password" ]]; then
    deploy_public_key_to_remote
    remote_auth_mode="key"
    remote_run "Verifying key-auth SSH" "$probe_cmd" "$backup_dir/ssh-key-probe.json" "$remote_timeout"
  fi
}

check_remote_port() {
  local check_cmd
  check_cmd="printf 'listeners:\n'; ss -lntup | grep -E ':(${port}|${health_port})\\b' || true; printf '\ncontainers:\n'; docker ps --format '{{.Names}} {{.Status}} {{.Ports}}' || true"

  if is_true "$dry_run"; then
    remote_run "Checking remote ports" "$check_cmd" "" "$remote_timeout"
    return
  fi

  info "Checking remote ports"
  local out
  out="$(remote_stdout "$check_cmd" "$remote_timeout")"
  printf "%s" "$out" | tee "$backup_dir/remote-before.txt"

  if printf "%s" "$out" | grep -Eq ":${port}[[:space:]]"; then
    if printf "%s" "$out" | grep -Eq ":${port}[[:space:]].*xboard-node"; then
      info "Target port is already owned by xboard-node"
      return
    fi

    warn "Target port $port appears occupied."
    if [[ -z "$remote_stop_command" ]] && ! is_true "$assume_yes"; then
      echo "Enter a remote command to free port $port, or leave empty to abort."
      echo "Example: cd /root/data/docker_data/glider2 && docker compose stop glider"
      read -r -p "Remote stop command: " remote_stop_command
    fi
    [[ -n "$remote_stop_command" ]] || die "port $port is occupied and no --remote-stop-command was provided"
    remote_run "Freeing remote port $port" "$remote_stop_command" "$backup_dir/remote-stop.json" "$remote_timeout"
  fi
}

install_or_restart_remote_node() {
  local installer_url install_cmd restart_cmd verify_cmd
  installer_url="https://raw.githubusercontent.com/cedar2025/xboard-node/dev/install.sh"
  install_cmd="curl -fsSL $(shell_quote "$installer_url") | bash -s -- --mode machine --panel $(shell_quote "$panel_url") --token $(shell_quote "$machine_token") --machine-id $(shell_quote "$machine_id") --kernel singbox --health-port $(shell_quote "$health_port") --yes"
  restart_cmd="if systemctl list-unit-files xboard-node.service >/dev/null 2>&1; then systemctl restart xboard-node; else echo 'xboard-node.service not installed'; exit 1; fi"

  if is_true "$skip_install"; then
    remote_run_allow_fail "Restarting existing xboard-node" "$restart_cmd" "$backup_dir/remote-restart.json" \
      || die "failed to restart xboard-node; see $backup_dir/remote-restart.json"
  else
    remote_run_allow_fail "Installing/updating xboard-node" "$install_cmd" "$backup_dir/remote-install.json" "$install_timeout" \
      || die "failed to install xboard-node; see $backup_dir/remote-install.json"
  fi

  verify_cmd="sleep 4; printf 'service:\n'; systemctl is-active xboard-node || true; systemctl --no-pager --full status xboard-node | sed -n '1,24p' || true; printf '\nlisteners:\n'; ss -lntup | grep -E ':(${port}|${health_port})\\b' || true; printf '\nhealth:\n'; curl -fsS http://127.0.0.1:${health_port}/healthz || true; printf '\nrecent logs:\n'; journalctl -u xboard-node -n 80 --no-pager || true"
  remote_run "Verifying remote xboard-node" "$verify_cmd" "$backup_dir/remote-after.json" "$remote_timeout"
}

open_remote_firewall() {
  if [[ "$open_firewall" == "false" ]]; then
    return
  fi

  local firewall_cmd
  firewall_cmd="set -e; if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then ufw allow ${port}/tcp comment 'Xboard Reality' || true; ufw status verbose; elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then firewall-cmd --permanent --add-port=${port}/tcp; firewall-cmd --reload; firewall-cmd --list-ports; else echo 'no active ufw/firewalld detected'; fi"
  remote_run_allow_fail "Opening remote firewall port $port/tcp" "$firewall_cmd" "$backup_dir/remote-firewall.json" \
    || die "failed to open remote firewall; see $backup_dir/remote-firewall.json"
}

verify_public_node_port() {
  if [[ "$verify_public_port" == "false" ]]; then
    return
  fi

  info "Verifying public TCP port $host:$port"
  if is_true "$dry_run"; then
    echo "DRY-RUN: would check /dev/tcp/$host/$port"
    return
  fi

  if timeout 8 bash -lc "</dev/tcp/$host/$port"; then
    echo "tcp_${port}=open" | tee "$backup_dir/public-port-check.txt"
  else
    echo "tcp_${port}=closed" | tee "$backup_dir/public-port-check.txt"
    die "public TCP port $host:$port is not reachable"
  fi
}

verify_panel_node() {
  info "Verifying Xboard node status"

  if is_true "$dry_run"; then
    echo "DRY-RUN: would verify Xboard node status"
    return
  fi

  local php_code
  php_code='
$n=\App\Models\Server::find((int) getenv("XBR_NODE_ID"));
if (!$n) { throw new RuntimeException("node not found"); }
$n->append(["last_check_at","is_online","available_status","metrics"]);
echo json_encode([
  "id"=>$n->id,
  "name"=>$n->name,
  "host"=>$n->host,
  "port"=>$n->port,
  "server_port"=>$n->server_port,
  "show"=>$n->show,
  "enabled"=>$n->enabled,
  "machine_id"=>$n->machine_id,
  "last_check_at"=>$n->last_check_at,
  "is_online"=>$n->is_online,
  "available_status"=>$n->available_status,
  "metrics"=>$n->metrics,
], JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE);
'

  docker exec -e XBR_NODE_ID="$node_id" "$container" php artisan tinker --execute="$php_code" | tee "$backup_dir/panel-node-after.json"
}

main() {
  parse_args "$@"
  require_local_tools
  collect_inputs
  preview

  if ! confirm "Continue with these settings?" "y"; then
    die "cancelled"
  fi

  make_backup_dir
  bootstrap_remote_ssh
  backup_database
  panel_upsert
  backup_database_after
  check_remote_port
  install_or_restart_remote_node
  open_remote_firewall
  verify_public_node_port
  verify_panel_node

  cat <<EOF

Done
  Backup dir:  $backup_dir
  Machine ID:  $machine_id
  Node ID:     $node_id
  Node action: $node_action
  Port:        $port

EOF
}

main "$@"
