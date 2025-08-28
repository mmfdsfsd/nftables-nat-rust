#!/bin/bash
# 必须是root用户
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# 下载可执行文件
curl -sSLf https://us.arloor.dev/https://github.com/mmfdsfsd/nftables-nat-rust/releases/download/v1.0.0/nat -o /tmp/nat
install /tmp/nat /usr/local/bin/nat

#安装nftables
apt update
apt install nftables -y

# 创建systemd服务
cat > /lib/systemd/system/nat.service <<EOF
[Unit]
Description=nat-service
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/nat
EnvironmentFile=/opt/nat/env
ExecStart=/usr/local/bin/nat /etc/nat.conf
ExecStop=/bin/bash -c 'nft add table ip self-nat; nft delete table ip self-nat; nft add table ip6 self-nat; nft delete table ip6 self-nat'
LimitNOFILE=100000
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

# 设置开机启动，并启动该服务
systemctl daemon-reload
systemctl enable nat

CONFIG_FILE="/etc/nat.conf"

mkdir -p /opt/nat
touch /opt/nat/env
touch $CONFIG_FILE

# 校验函数
validate_rule() {
    local rule="$1"

    if [[ "$rule" =~ ^SINGLE,([0-9]{1,5}),([0-9]{1,5}),([a-zA-Z0-9.-]+)$ ]]; then
        local p1=${BASH_REMATCH[1]}
        local p2=${BASH_REMATCH[2]}
        if (( p1 >=1 && p1 <=65535 && p2 >=1 && p2 <=65535 )); then
            return 0
        fi
    elif [[ "$rule" =~ ^RANGE,([0-9]{1,5}),([0-9]{1,5}),([a-zA-Z0-9.-]+)$ ]]; then
        local start=${BASH_REMATCH[1]}
        local end=${BASH_REMATCH[2]}
        if (( start >=1 && start <=65535 && end >=1 && end <=65535 && start <= end )); then
            return 0
        fi
    fi
    return 1
}

# 配置管理菜单
manage_config() {
    while true; do
        echo
        echo "====== NAT 配置管理 ======"
        echo "1) 查看当前配置"
        echo "2) 新增规则"
        echo "3) 修改规则"
        echo "4) 删除规则"
        echo "5) 退出并应用配置"
        read -rp "请选择操作: " op

        case "$op" in
            1)
                echo "当前配置 ($CONFIG_FILE):"
                nl -w2 -s". " $CONFIG_FILE
                ;;
            2) # 新增规则
                echo "选择规则类型:"
                echo "1) 单端口 (SINGLE)"
                echo "2) 端口范围 (RANGE)"
                read -rp "请输入数字 (1 或 2): " type_choice

                case "$type_choice" in
                    1)
                        read -rp "请输入本地端口号: " local_port
                        read -rp "请输入远程端口号: " remote_port
                        read -rp "请输入转发的域名: " domain
                        newline="SINGLE,${local_port},${remote_port},${domain}"
                        ;;
                    2)
                        read -rp "请输入本地起始端口号: " local_start
                        read -rp "请输入本地结束端口号: " local_end
                        read -rp "请输入转发的域名: " domain
                        newline="RANGE,${local_start},${local_end},${domain}"
                        ;;
                    *)
                        echo "❌ 无效选择，返回菜单。"
                        continue
                        ;;
                esac

                if validate_rule "$newline"; then
                    echo "$newline" >> $CONFIG_FILE
                    echo "✅ 新增成功：$newline"
                else
                    echo "❌ 规则格式不合法，请重试。"
                fi
                ;;
            3) # 修改规则
                nl -w2 -s". " $CONFIG_FILE
                read -rp "请输入要修改的规则编号: " num
                line=$(sed -n "${num}p" $CONFIG_FILE)
                if [ -z "$line" ]; then
                    echo "编号无效。"
                else
                    echo "当前规则: $line"
                    echo "选择新规则类型:"
                    echo "1) 单端口 (SINGLE)"
                    echo "2) 端口范围 (RANGE)"
                    read -rp "请输入数字 (1 或 2): " type_choice

                    case "$type_choice" in
                        1)
                            read -rp "请输入本地端口号: " local_port
                            read -rp "请输入远程端口号: " remote_port
                            read -rp "请输入转发的域名: " domain
                            newline="SINGLE,${local_port},${remote_port},${domain}"
                            ;;
                        2)
                            read -rp "请输入本地起始端口号: " local_start
                            read -rp "请输入本地结束端口号: " local_end
                            read -rp "请输入转发的域名: " domain
                            newline="RANGE,${local_start},${local_end},${domain}"
                            ;;
                        *)
                            echo "❌ 无效选择，修改取消。"
                            continue
                            ;;
                    esac

                    if validate_rule "$newline"; then
                        sed -i "${num}s/.*/${newline}/" $CONFIG_FILE
                        echo "✅ 修改完成：$newline"
                    else
                        echo "❌ 规则格式不合法，修改未保存。"
                    fi
                fi
                ;;
            4) # 删除规则
                nl -w2 -s". " $CONFIG_FILE
                read -rp "请输入要删除的规则编号: " num
                sed -i "${num}d" $CONFIG_FILE
                echo "✅ 删除完成。"
                ;;
            5)
                echo "保存并应用配置..."
                systemctl restart nat
                echo "nat 服务已重启。"
                break
                ;;
            *)
                echo "无效输入。"
                ;;
        esac
    done
}

manage_config
