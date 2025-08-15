#!/bin/bash
# sync-to-k8s-nodes.sh
# 用法：./sync-to-k8s-nodes.sh /abs/path/file  [m|w]

# 1. 参数个数检查
[[ $# -lt 1 ]] && {
    echo "Usage: $0 /abs/path/file [mode: m|w]"
    exit 1
}

src=$1
mode=${2:-all}                       # 缺省为 all（5 台都传）

# 2. 文件/目录存在性检查
[[ ! -e $src ]] && {
    echo "[ $src ] not found!"
    exit 2
}

fullpath=$(dirname "$src")
basename=$(basename "$src")

# 3. 根据 mode 决定目标节点
case "$mode" in
    m|MASTER_NODE)
        K8S_NODES=(ubuntu-master02 ubuntu-master03)
        ;;
    w|WORKER_NODE)
        K8S_NODES=(ubuntu-node01 ubuntu-node02 ubuntu-node03)
        ;;
    *)
        K8S_NODES=(ubuntu-master02 ubuntu-master03 ubuntu-node01 ubuntu-node02 ubuntu-node03)
        ;;
esac

# 4. 遍历推送
for host in "${K8S_NODES[@]}"; do
    tput setaf 2
    echo "===== rsyncing ${host}: $basename ====="
    tput setaf 7

    # -P 显示进度；-e ssh 指定协议
    rsync -azP -e ssh "$src" "$(whoami)@${host}:${fullpath}/"

    if [[ $? -eq 0 ]]; then
        echo "✅  ${host} 同步成功"
    else
        echo "❌  ${host} 同步失败"
    fi
done
