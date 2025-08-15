#!/bin/bash

# ===============================================
# data_rsync.sh - 优化版 Kubernetes 节点同步脚本
# 说明：将本地指定文件或目录，同步到一组 Kubernetes 节点
# 功能特性：
#   - 支持批量文件/目录同步
#   - 支持通过配置文件自定义节点组
#   - 支持只同步 master/worker 节点或全部节点
#   - 支持自定义用户名、SSH 端口
#   - 支持 dry-run 预演、排除模式
#   - 支持自定义目标路径
#   - 同步日志保存
# 用法示例：
#   ./data_rsync.sh /file1 /dir2 ... [选项]
# 常用选项：
#   -m 仅同步到 master 节点
#   -w 仅同步到 worker 节点
#   -c <config> 指定节点配置文件
#   -u <user>   指定用户名
#   -p <port>   指定 ssh 端口
#   -d          dry-run 仅预演
#   -e <pattern>排除指定模式文件，支持多次
#   -t <path>   指定同步目标路径
#   -h          显示帮助
# ===============================================

set -e  # 脚本遇到错误即退出

# 显示帮助信息
show_help() {
  cat <<EOF
用法: $0 [源文件/目录1] [源文件/目录2] ... [选项]
选项:
  -m                只同步到 master 节点
  -w                只同步到 worker 节点
  -c <config>       节点配置文件，格式: 节点组名:host1,host2,...
  -u <user>         指定同步用户名（默认当前用户）
  -p <port>         指定 SSH 端口
  -d                dry-run 仅预演同步内容
  -e <pattern>      同步排除模式，可多次传递
  -t <target_path>  指定目标目录（默认与源路径一致）
  -h                显示帮助
EOF
  exit 1
}

# ========== 初始化默认参数 ==========
MODE=all           # 默认全部节点
CONFIG_FILE=""     # 默认无节点配置文件
USER="$(whoami)"   # 默认当前系统用户
PORT=""            # 默认22端口
DRYRUN=""          # 默认非 dry-run
EXCLUDES=()        # 排除模式数组
TARGET_PATH=""     # 默认目标路径与源一致
LOG_FILE="rsync_$(date +'%Y%m%d_%H%M%S').log"  # 日志文件名，含时间戳

# ========== 解析参数 ==========
ARGS=()            # 源文件/目录参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m) MODE="master"; shift ;;             # 只同步到 master 节点
    -w) MODE="worker"; shift ;;             # 只同步到 worker 节点
    -c) CONFIG_FILE="$2"; shift 2 ;;        # 指定节点配置文件
    -u) USER="$2"; shift 2 ;;               # 指定用户名
    -p) PORT="$2"; shift 2 ;;               # 指定 ssh 端口
    -d) DRYRUN="--dry-run"; shift ;;        # dry-run 预演
    -e) EXCLUDES+=("$2"); shift 2 ;;        # 添加排除模式
    -t) TARGET_PATH="$2"; shift 2 ;;        # 指定目标路径
    -h) show_help ;;                        # 显示帮助
    --) shift; break ;;                     # 参数分隔符
    -*) echo "未知参数: $1"; show_help ;;   # 未知参数处理
    *) ARGS+=("$1"); shift ;;               # 普通参数作为同步源
  esac
done

# ========== 参数检查 ==========
if [[ ${#ARGS[@]} -eq 0 ]]; then
  echo "请指定至少一个文件/目录!"
  show_help
fi

# ========== 加载节点配置 ==========
if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
  # 配置文件格式需定义 MASTER_NODES 和 WORKER_NODES 两组变量
  source "$CONFIG_FILE"
else
  # 默认节点组
  MASTER_NODES=(ubuntu-master02 ubuntu-master03)
  WORKER_NODES=(ubuntu-node01 ubuntu-node02 ubuntu-node03)
fi

# 根据模式选择目标节点组
case "$MODE" in
  master) K8S_NODES=("${MASTER_NODES[@]}") ;;         # master 节点组
  worker) K8S_NODES=("${WORKER_NODES[@]}") ;;         # worker 节点组
  *)      K8S_NODES=("${MASTER_NODES[@]}" "${WORKER_NODES[@]}") ;; # 全部节点
esac

# ========== 组装 rsync 参数 ==========
RSYNC_OPTS=(-azP)                                # -a归档，-z压缩，-P进度
if [[ -n "$PORT" ]]; then
  RSYNC_OPTS+=(-e "ssh -p $PORT")                # 指定SSH端口
else
  RSYNC_OPTS+=(-e "ssh")
fi
[[ -n "$DRYRUN" ]] && RSYNC_OPTS+=("$DRYRUN")    # dry-run参数
for ex in "${EXCLUDES[@]}"; do
  RSYNC_OPTS+=(--exclude="$ex")                  # 添加排除模式
done

# ========== 核心同步循环 ==========
for src in "${ARGS[@]}"; do
  # 检查源文件/目录是否存在
  if [[ ! -e "$src" ]]; then
    echo "[ $src ] 不存在, 跳过."
    continue
  fi
  fullpath=$(dirname "$src")                     # 源文件父目录
  basename=$(basename "$src")                    # 源文件名/目录名
  tgtpath="${TARGET_PATH:-$fullpath}"            # 目标路径，默认与源路径一致

  # 遍历目标节点，逐个同步
  for host in "${K8S_NODES[@]}"; do
    tput setaf 2; echo "===== 正在同步 ${host}: $basename ====="; tput setaf 7

    # 执行 rsync，同步文件到远程节点对应路径（保留文件名/目录名）
    rsync "${RSYNC_OPTS[@]}" "$src" "${USER}@${host}:$tgtpath/" | tee -a "$LOG_FILE"

    # 检查同步结果，提示成功或失败
    if [[ \\${PIPESTATUS[0]} -eq 0 ]]; then
      echo "✅  ${host} 同步成功" | tee -a "$LOG_FILE"
    else
      echo "❌  ${host} 同步失败" | tee -a "$LOG_FILE"
    fi
  done
done

echo "同步日志已保存至 $LOG_FILE"