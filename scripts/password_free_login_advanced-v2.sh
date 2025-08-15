#!/bin/bash
# password_free_login_advanced.sh
# 批量实现多台主机SSH免密登录的增强脚本
# 支持自定义用户名、端口、密钥类型、密钥路径、主机列表文件、重试机制等
# 用法示例：
#   ./password_free_login_advanced.sh -u root -p 2222 -f hosts.txt
#   ./password_free_login_advanced.sh 192.168.1.10 192.168.1.11
#   ./password_free_login_advanced.sh -t ed25519 -k ~/.ssh/id_ed25519 -f hosts.txt

set -e  # 一旦脚本执行出错即退出

# 默认参数初始化
PORT=22                      # SSH端口，默认22
KEY_TYPE="rsa"               # 密钥类型，默认rsa
KEY_BITS=2048                # 密钥长度，默认2048
USERNAME="root"              # 远程用户名，默认root
KEY_FILE="$HOME/.ssh/id_${KEY_TYPE}"   # 密钥文件路径，默认~/.ssh/id_rsa
HOST_FILE=""                 # 主机列表文件，默认为空
HOSTS=()                     # 主机数组
RETRY=2                      # 密钥推送失败重试次数
FAILED_HOSTS=()              # 推送失败主机记录

# 帮助信息
usage() {
    echo "用法: $0 [-u 用户名] [-p 端口] [-k 密钥文件] [-t 密钥类型] [-b 密钥长度] [-f 主机文件] [主机1 主机2 ...]"
    echo "示例: $0 -u root -p 2222 -f hosts.txt"
    exit 1
}

# 解析输入参数
while getopts ":u:p:k:t:b:f:h" opt; do
    case $opt in
        u) USERNAME="$OPTARG" ;;         # 指定远程用户名
        p) PORT="$OPTARG" ;;             # 指定SSH端口
        k) KEY_FILE="$OPTARG" ;;         # 指定密钥文件路径
        t) KEY_TYPE="$OPTARG" ;;         # 指定密钥类型
        b) KEY_BITS="$OPTARG" ;;         # 指定密钥长度
        f) HOST_FILE="$OPTARG" ;;        # 指定主机列表文件
        h) usage ;;                     # 显示帮助信息
        *) usage ;;                     # 其他参数显示帮助信息
    esac
done
shift $((OPTIND -1))

# 根据参数决定主机列表来源
if [[ -n "$HOST_FILE" ]]; then
    mapfile -t HOSTS < "$HOST_FILE"  # 从host文件读取主机，每行一个
else
    HOSTS=("$@")                     # 从命令行参数读取主机
fi

# 没有主机则报错
if [[ ${#HOSTS[@]} -eq 0 ]]; then
    echo "未指定主机。"
    usage
fi

# 步骤一：自动生成密钥（如果未存在）
if [[ ! -f "$KEY_FILE" ]]; then
    echo "生成 $KEY_TYPE 密钥：$KEY_FILE"
    ssh-keygen -t $KEY_TYPE -b $KEY_BITS -P "" -f "$KEY_FILE" -q
    # -t 指定类型，-b 指定长度，-P "" 表示无口令，-f 目标文件，-q 静默模式
fi

# 步骤二：读取目标主机通用密码（不回显，保证安全）
read -s -p "请输入所有节点统一密码: " PASSWORD
echo

# 步骤三：检测并安装 expect 工具（用于自动交互）
if ! command -v expect >/dev/null; then
    if command -v yum >/dev/null; then
        yum install -y expect
    elif command -v apt-get >/dev/null; then
        apt-get install -y expect
    elif command -v dnf >/dev/null; then
        dnf install -y expect
    elif command -v zypper >/dev/null; then
        zypper install -y expect
    else
        echo "无法自动安装 expect，请手动安装！"
        exit 1
    fi
fi

# 步骤四：遍历主机批量推送公钥
for host in "${HOSTS[@]}"; do
    echo ">>> 正在处理 $host:$PORT（用户名：$USERNAME）"
    success=0
    for attempt in $(seq 1 $RETRY); do
        # 使用expect自动处理ssh-copy-id交互，包含首次连接时的yes确认和密码输入
        expect <<EOF
set timeout 20
spawn ssh-copy-id -i ${KEY_FILE}.pub -p $PORT $USERNAME@$host
expect {
    "yes/no"    { send "yes\r"; exp_continue }     # 首次连接自动输入yes
    "password:" { send "$PASSWORD\r" }
    timeout     { exit 2 }
}
expect eof
EOF
        # 自动测试是否免密（ssh BatchMode测试）
        if ssh -o BatchMode=yes -o ConnectTimeout=8 -p $PORT $USERNAME@$host "echo success" 2>/dev/null | grep -q success; then
            echo "[$host] 密钥推送成功，已实现免密！"
            success=1
            break
        else
            echo "[$host] 第$attempt次推送失败，重试..."
        fi
    done
    if [[ $success -ne 1 ]]; then
        FAILED_HOSTS+=("$host")
        echo "[$host] 密钥推送失败！"
    fi
done

# 步骤五：结果汇总
if [[ ${#FAILED_HOSTS[@]} -gt 0 ]]; then
    echo "以下主机推送失败，请检查网络/密码/端口/用户名/防火墙："
    printf "%s\n" "${FAILED_HOSTS[@]}"
else
    echo "全部完成！所有主机已实现免密登录。"
fi
