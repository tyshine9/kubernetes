#!/bin/bash
# password_free_login.sh
# 用法：./password_free_login.sh  [port]   # 默认 22

set -e
PORT=${1:-22}                     # 支持自定义端口
KEY_FILE=/root/.ssh/id_rsa        # 密钥保存位置
HOSTS=(ubuntu-master01 ubuntu-master02 ubuntu-master03 ubuntu-node01 ubuntu-node02 ubuntu-node03)

# 1. 生成密钥（如果已存在就跳过）
[ -f "$KEY_FILE" ] || ssh-keygen -t rsa -b 2048 -P "" -f "$KEY_FILE" -q

# 2. 交互式读密码（屏幕不回显）
read -s -p "请输入所有节点统一密码: " PASSWORD
echo

# 3. 安装 expect（如未装）
command -v expect >/dev/null 2>&1 || yum install -y expect || apt-get install -y expect

# 4. 批量推送公钥
for host in "${HOSTS[@]}"; do
    echo ">>> 处理 $host:$PORT"
    expect <<EOF
set timeout 10
spawn ssh-copy-id -i ${KEY_FILE}.pub -p $PORT root@$host
expect {
    "yes/no"    { send "yes\r"; exp_continue }
    "password:" { send "$PASSWORD\r" }
}
expect eof
EOF
done
echo "全部完成！"
