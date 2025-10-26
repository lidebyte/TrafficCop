#!/bin/bash

# 设置新的工作目录
WORK_DIR="/root/TrafficCop"
mkdir -p "$WORK_DIR"

# 导入端口流量辅助函数
if [ -f "$WORK_DIR/port_traffic_helper.sh" ]; then
    source "$WORK_DIR/port_traffic_helper.sh"
fi

# 更新文件路径
CONFIG_FILE="$WORK_DIR/tg_notifier_config.txt"
LOG_FILE="$WORK_DIR/traffic_monitor.log"
LAST_NOTIFICATION_FILE="$WORK_DIR/last_traffic_notification"
SCRIPT_PATH="$WORK_DIR/tg_notifier.sh"
CRON_LOG="$WORK_DIR/tg_notifier_cron.log"

# 文件迁移函数
migrate_files() {
    # 迁移配置文件
    if [ -f "/root/tg_notifier_config.txt" ]; then
        mv "/root/tg_notifier_config.txt" "$CONFIG_FILE"
    fi

    # 迁移日志文件
    if [ -f "/root/traffic_monitor.log" ]; then
        mv "/root/traffic_monitor.log" "$LOG_FILE"
    fi

    # 迁移最后通知文件
    if [ -f "/tmp/last_traffic_notification" ]; then
        mv "/tmp/last_traffic_notification" "$LAST_NOTIFICATION_FILE"
    fi

    # 迁移脚本文件
    if [ -f "/root/tg_notifier.sh" ]; then
        mv "/root/tg_notifier.sh" "$SCRIPT_PATH"
    fi

    # 迁移 cron 日志文件
    if [ -f "/root/tg_notifier_cron.log" ]; then
        mv "/root/tg_notifier_cron.log" "$CRON_LOG"
    fi

    # 更新 crontab 中的脚本路径
    if crontab -l | grep -q "/root/tg_notifier.sh"; then
        crontab -l | sed "s|/root/tg_notifier.sh|$SCRIPT_PATH|g" | crontab -
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') 文件已迁移到新的工作目录: $WORK_DIR" | tee -a "$CRON_LOG"
}

# 在脚本开始时调用迁移函数
migrate_files

# 切换到工作目录
cd "$WORK_DIR" || exit 1

# 设置时区为上海（东八区）
export TZ='Asia/Shanghai'

echo "----------------------------------------------"| tee -a "$CRON_LOG"
echo "$(date '+%Y-%m-%d %H:%M:%S') : 版本号：9.5"  

# 检查是否有同名的 crontab 正在执行:
check_running() {
    # 新增：添加日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查是否有其他实例运行" >> "$CRON_LOG"
    if pidof -x "$(basename "\$0")" -o $$ > /dev/null; then
        # 新增：添加日志
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 另一个脚本实例正在运行，退出脚本" >> "$CRON_LOG"
        echo "另一个脚本实例正在运行，退出脚本"
        exit 1
    fi
    # 新增：添加日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 没有其他实例运行，继续执行" >> "$CRON_LOG"
}


# 函数：获取非空输入
get_valid_input() {
    local prompt="${1:-"请输入："}"
    local input=""
    while true; do
        read -p "${prompt}" input
        if [[ -n "${input}" ]]; then
            echo "${input}"
            return
        else
            echo "输入不能为空，请重新输入。"
        fi
    done
}


# 读取配置
read_config() {
    if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
        echo "配置文件不存在或为空，需要进行初始化配置。"
        return 1
    fi

    # 读取配置文件
    source "$CONFIG_FILE"

    # 检查必要的配置项是否都存在
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] || [ -z "$MACHINE_NAME" ] || [ -z "$DAILY_REPORT_TIME" ]; then
        echo "配置文件不完整，需要重新进行配置。"
        return 1
    fi

    return 0
}

# 写入配置
write_config() {
    cat > "$CONFIG_FILE" << EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
DAILY_REPORT_TIME="$DAILY_REPORT_TIME"
MACHINE_NAME="$MACHINE_NAME"
EOF
    echo "配置已保存到 $CONFIG_FILE"
}


# 初始配置
initial_config() {
    echo "======================================"
    echo "   修改 Telegram 通知配置"
    echo "======================================"
    echo ""
    echo "提示：按 Enter 保留当前配置，输入新值则更新配置"
    echo ""
    
    local new_token new_chat_id new_machine_name new_daily_report_time

    # Bot Token
    if [ -n "$BOT_TOKEN" ]; then
        # 隐藏部分Token显示
        local token_display="${BOT_TOKEN:0:10}...${BOT_TOKEN: -4}"
        echo "请输入Telegram Bot Token [当前: $token_display]: "
    else
        echo "请输入Telegram Bot Token: "
    fi
    read -r new_token
    # 如果输入为空且有原配置，保留原配置
    if [[ -z "$new_token" ]] && [[ -n "$BOT_TOKEN" ]]; then
        new_token="$BOT_TOKEN"
        echo "  → 保留原配置"
    fi
    # 如果还是空（首次配置），要求必须输入
    while [[ -z "$new_token" ]]; do
        echo "Bot Token 不能为空。请重新输入: "
        read -r new_token
    done

    # Chat ID
    if [ -n "$CHAT_ID" ]; then
        echo "请输入Telegram Chat ID [当前: $CHAT_ID]: "
    else
        echo "请输入Telegram Chat ID: "
    fi
    read -r new_chat_id
    if [[ -z "$new_chat_id" ]] && [[ -n "$CHAT_ID" ]]; then
        new_chat_id="$CHAT_ID"
        echo "  → 保留原配置"
    fi
    while [[ -z "$new_chat_id" ]]; do
        echo "Chat ID 不能为空。请重新输入: "
        read -r new_chat_id
    done

    # 机器名称
    if [ -n "$MACHINE_NAME" ]; then
        echo "请输入机器名称 [当前: $MACHINE_NAME]: "
    else
        echo "请输入机器名称: "
    fi
    read -r new_machine_name
    if [[ -z "$new_machine_name" ]] && [[ -n "$MACHINE_NAME" ]]; then
        new_machine_name="$MACHINE_NAME"
        echo "  → 保留原配置"
    fi
    while [[ -z "$new_machine_name" ]]; do
        echo "机器名称不能为空。请重新输入: "
        read -r new_machine_name
    done

    # 每日报告时间
    if [ -n "$DAILY_REPORT_TIME" ]; then
        echo "请输入每日报告时间 [当前: $DAILY_REPORT_TIME，格式 HH:MM]: "
    else
        echo "请输入每日报告时间 (时区已经固定为东八区，输入格式为 HH:MM，例如 01:00): "
    fi
    read -r new_daily_report_time
    if [[ -z "$new_daily_report_time" ]] && [[ -n "$DAILY_REPORT_TIME" ]]; then
        new_daily_report_time="$DAILY_REPORT_TIME"
        echo "  → 保留原配置"
    fi
    while [[ ! $new_daily_report_time =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; do
        echo "时间格式不正确。请重新输入 (HH:MM): "
        read -r new_daily_report_time
    done

    # 更新配置文件（使用引号防止空格等特殊字符问题）
    BOT_TOKEN="$new_token"
    CHAT_ID="$new_chat_id"
    MACHINE_NAME="$new_machine_name"
    DAILY_REPORT_TIME="$new_daily_report_time"
    
    write_config
    
    echo ""
    echo "======================================"
    echo "配置已更新成功！"
    echo "======================================"
    echo ""
    read_config
}

# 发送限速警告
send_throttle_warning() {
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local port_summary=$(get_port_traffic_summary_for_tg)
    local message="⚠️ [${MACHINE_NAME}]限速警告：流量已达到限制，已启动 TC 模式限速。${port_summary}"
    curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message"
}

# 获取端口流量摘要（专为Telegram格式化）
get_port_traffic_summary_for_tg() {
    # 如果有 port_traffic_helper.sh 中的函数，优先使用
    if command -v get_port_traffic_summary &> /dev/null; then
        local summary=$(get_port_traffic_summary 5)
        if [ -n "$summary" ]; then
            # 转换换行符为URL编码格式
            echo "$summary" | sed 's/\n/%0A/g'
            return
        fi
    fi
    
    # 兼容性实现（如果port_traffic_helper.sh不可用）
    local ports_config_file="$WORK_DIR/ports_traffic_config.json"
    local summary=""
    
    if [ ! -f "$ports_config_file" ]; then
        return
    fi
    
    # 检查是否有端口配置
    local port_count=$(jq -r '.ports | length' "$ports_config_file" 2>/dev/null)
    if [ -z "$port_count" ] || [ "$port_count" -eq 0 ]; then
        return
    fi
    
    summary="%0A%0A🔌 端口流量详情："
    
    # 使用与view_port_traffic.sh相同的方法获取流量
    if [ -f "$WORK_DIR/view_port_traffic.sh" ]; then
        local port_data=$(bash "$WORK_DIR/view_port_traffic.sh" --json 2>/dev/null)
        if [ -n "$port_data" ]; then
            local max_display=5
            local displayed=0
            
            for ((i=0; i<port_count && displayed<max_display; i++)); do
                local port=$(echo "$port_data" | jq -r ".ports[$i].port" 2>/dev/null)
                local port_usage=$(echo "$port_data" | jq -r ".ports[$i].usage" 2>/dev/null)
                local port_limit=$(echo "$port_data" | jq -r ".ports[$i].limit" 2>/dev/null)
                
                if [ -n "$port" ] && [ "$port" != "null" ]; then
                    local port_percentage=0
                    if (( $(echo "$port_limit > 0" | bc -l 2>/dev/null || echo "0") )); then
                        port_percentage=$(echo "scale=0; ($port_usage / $port_limit) * 100" | bc 2>/dev/null || echo "0")
                    fi
                    summary="${summary}%0A✓ 端口 ${port}: ${port_usage}GB / ${port_limit}GB (${port_percentage}%)"
                    displayed=$((displayed + 1))
                fi
            done
            
            if [ "$port_count" -gt "$max_display" ]; then
                summary="${summary}%0A...及其他 $((port_count - max_display)) 个端口"
            fi
        fi
    fi
    
    echo "$summary"
}

# 发送限速解除通知
send_throttle_lifted() {
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local port_summary=$(get_port_traffic_summary_for_tg)
    local message="✅ [${MACHINE_NAME}]限速解除：流量已恢复正常，所有限制已清除。${port_summary}"
    curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message"
}

# 发送新周期开始通知
send_new_cycle_notification() {
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local message="🔄 [${MACHINE_NAME}]新周期开始：新的流量统计周期已开始，之前的限速（如果有）已自动解除。"
    curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message"
}

# 发送关机警告
send_shutdown_warning() {
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local port_summary=$(get_port_traffic_summary_for_tg)
    local message="🚨 [${MACHINE_NAME}]关机警告：流量已达到严重限制，系统将在 1 分钟后关机！${port_summary}"
    curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message"
}




test_telegram_notification() {
    local message="🔔 [${MACHINE_NAME}]这是一条测试消息。如果您收到这条消息，说明Telegram通知功能正常工作。"
    local response
    response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${message}" \
        -d "disable_notification=true")
    
    if echo "$response" | grep -q '"ok":true'; then
        echo "✅ [${MACHINE_NAME}]测试消息已成功发送，请检查您的Telegram。"
    else
        echo "❌ [${MACHINE_NAME}]发送测试消息失败。请检查您的BOT_TOKEN和CHAT_ID设置。"
    fi
}

check_and_notify() { 
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始检查流量状态..."| tee -a "$CRON_LOG"
    
    local current_status="未知"
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local relevant_log=""
    
    # 从后往前读取日志文件，找到第一个包含相关信息的行
    relevant_log=$(tac "$LOG_FILE" | grep -m 1 -E "流量超出限制|使用 TC 模式限速|新的流量周期开始|流量正常，清除所有限制")
    
    # 记录相关的日志内容
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 相关的日志内容: $relevant_log"| tee -a "$CRON_LOG"
    
    # 确定当前状态
    if echo "$relevant_log" | grep -q "流量超出限制，系统将在 1 分钟后关机"; then
        current_status="关机"
    elif echo "$relevant_log" | grep -q "流量超出限制"; then
        current_status="限速"
    elif echo "$relevant_log" | grep -q "新的流量周期开始，重置限制"; then
        current_status="新周期"
    elif echo "$relevant_log" | grep -q "流量正常，清除所有限制"; then
        current_status="正常"
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 当前检测到的状态: $current_status"| tee -a "$CRON_LOG"
    
    local last_status=""
    if [ -f "$LAST_NOTIFICATION_FILE" ]; then
        last_status=$(tail -n 1 "$LAST_NOTIFICATION_FILE" | cut -d' ' -f3-)
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 上次记录的状态: $last_status"| tee -a "$CRON_LOG"
    
    # 根据状态调用相应的通知函数
    if [ "$current_status" = "限速" ] && [ "$last_status" != "限速" ]; then
        send_throttle_warning
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 已调用 send_throttle_warning"| tee -a "$CRON_LOG"
    elif [ "$current_status" = "正常" ] && [ "$last_status" = "限速" ]; then
        send_throttle_lifted
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 已调用 send_throttle_lifted"| tee -a "$CRON_LOG"
    elif [ "$current_status" = "新周期" ]; then
        send_new_cycle_notification
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 已调用 send_new_cycle_notification"| tee -a "$CRON_LOG"
    elif [ "$current_status" = "关机" ]; then
        send_shutdown_warning
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 已调用 send_shutdown_warning"| tee -a "$CRON_LOG"
    elif [ "$current_status" = "未知" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法识别当前状态，不发送通知"| tee -a "$CRON_LOG"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 无需发送通知"| tee -a "$CRON_LOG"
    fi
    
    # 追加新状态到状态文件
    echo "$current_time $current_status" >> "$LAST_NOTIFICATION_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 已追加新状态到状态文件"| tee -a "$CRON_LOG"
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 流量检查完成。"| tee -a "$CRON_LOG"
}




# 设置定时任务
setup_cron() {
    local correct_entry="* * * * * $SCRIPT_PATH -cron"
    local current_crontab=$(crontab -l 2>/dev/null)
    local tg_notifier_entries=$(echo "$current_crontab" | grep "tg_notifier.sh")
    local correct_entries_count=$(echo "$tg_notifier_entries" | grep -F "$correct_entry" | wc -l)

    if [ "$correct_entries_count" -eq 1 ]; then
        echo "正确的 crontab 项已存在且只有一个，无需修改。"
    else
        # 删除所有包含 tg_notifier.sh 的条目
        new_crontab=$(echo "$current_crontab" | grep -v "tg_notifier.sh")
        
        # 添加一个正确的条目
        new_crontab="${new_crontab}
$correct_entry"

        # 更新 crontab
        echo "$new_crontab" | crontab -

        echo "已更新 crontab。删除了所有旧的 tg_notifier.sh 条目，并添加了一个每分钟执行的条目。"
    fi

    # 显示当前的 crontab 内容
    echo "当前的 crontab 内容："
    crontab -l
}

# 每日报告
daily_report() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 开始生成每日报告"| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : DAILY_REPORT_TIME=$DAILY_REPORT_TIME"| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : BOT_TOKEN=${BOT_TOKEN:0:5}... CHAT_ID=$CHAT_ID"| tee -a "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 日志文件路径: $LOG_FILE"| tee -a "$CRON_LOG"

    # 反向读取日志文件，查找第一个同时包含"当前使用流量"和"限制流量"的行
    local usage_line=$(tac "$LOG_FILE" | grep -m 1 -E "当前使用流量:.*限制流量:")

    if [[ -z "$usage_line" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法在日志中找到同时包含当前使用流量和限制流量的行"| tee -a "$CRON_LOG"
        return 1
    fi

    local current_usage=$(echo "$usage_line" | grep -oP '当前使用流量:\s*\K[0-9.]+ [GBMKgbmk]+')
    local limit=$(echo "$usage_line" | grep -oP '限制流量:\s*\K[0-9.]+ [GBMKgbmk]+')

    if [[ -z "$current_usage" || -z "$limit" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法从行中提取流量信息"| tee -a "$CRON_LOG"
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 问题行: $usage_line"| tee -a "$CRON_LOG"
        return 1
    fi

    # 构建基础消息
    local message="📊 [${MACHINE_NAME}]每日流量报告%0A%0A🖥️ 机器总流量：%0A当前使用：$current_usage%0A流量限制：$limit"
    
    # 检查是否有端口流量配置
    local ports_config_file="$WORK_DIR/ports_traffic_config.json"
    local view_script="$WORK_DIR/view_port_traffic.sh"
    
    if [ -f "$ports_config_file" ]; then
        local port_count=$(jq -r '.ports | length' "$ports_config_file" 2>/dev/null || echo "0")
        
        if [ "$port_count" -gt 0 ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 检测到 $port_count 个端口流量配置，添加端口信息"| tee -a "$CRON_LOG"
            
            # 如果有 view_port_traffic.sh 脚本，使用它
            if [ -f "$view_script" ]; then
                local port_data=$(bash "$view_script" --json 2>/dev/null)
            else
                # 否则直接读取配置文件和 iptables 统计
                local port_data=""
            fi
            
            if [ -n "$port_data" ] && echo "$port_data" | jq -e '.ports' >/dev/null 2>&1; then
                local actual_port_count=$(echo "$port_data" | jq -r '.ports | length' 2>/dev/null || echo "0")
                
                if [ "$actual_port_count" -gt 0 ]; then
                    message="${message}%0A%0A🔌 端口流量详情："
                    
                    # 遍历每个端口
                    local i=0
                    while [ $i -lt $actual_port_count ]; do
                        local port=$(echo "$port_data" | jq -r ".ports[$i].port" 2>/dev/null)
                        local port_desc=$(echo "$port_data" | jq -r ".ports[$i].description" 2>/dev/null)
                        local port_usage=$(echo "$port_data" | jq -r ".ports[$i].usage" 2>/dev/null)
                        local port_limit=$(echo "$port_data" | jq -r ".ports[$i].limit" 2>/dev/null)
                        
                        if [ -n "$port" ] && [ "$port" != "null" ] && [ "$port_usage" != "null" ]; then
                            # 格式化流量显示（保留2位小数）
                            local port_usage_formatted=$(printf "%.2f" "$port_usage" 2>/dev/null || echo "$port_usage")
                            local port_limit_formatted=$(printf "%.2f" "$port_limit" 2>/dev/null || echo "$port_limit")
                            
                            # 根据使用率选择表情
                            local port_percentage=0
                            if [ -n "$port_limit" ] && [ "$port_limit" != "null" ] && (( $(echo "$port_limit > 0" | bc -l 2>/dev/null || echo "0") )); then
                                port_percentage=$(printf "%.2f" $(echo "scale=2; ($port_usage / $port_limit) * 100" | bc 2>/dev/null || echo "0"))
                            fi
                            
                            local status_icon="✅"
                            if (( $(echo "$port_percentage >= 90" | bc -l 2>/dev/null || echo "0") )); then
                                status_icon="🔴"
                            elif (( $(echo "$port_percentage >= 75" | bc -l 2>/dev/null || echo "0") )); then
                                status_icon="🟡"
                            fi
                            
                            message="${message}%0A${status_icon} 端口 ${port} (${port_desc})：${port_usage_formatted}GB / ${port_limit_formatted}GB"
                        fi
                        
                        i=$((i + 1))
                    done
                    
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : 已添加 $actual_port_count 个端口的流量信息"| tee -a "$CRON_LOG"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') : JSON数据中没有端口信息"| tee -a "$CRON_LOG"
                fi
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 无法获取有效的端口流量JSON数据"| tee -a "$CRON_LOG"
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 没有配置端口流量监控"| tee -a "$CRON_LOG"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 端口配置文件不存在"| tee -a "$CRON_LOG"
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 准备发送消息"| tee -a "$CRON_LOG"

    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    local response

    echo "$(date '+%Y-%m-%d %H:%M:%S') : 尝试发送Telegram消息"| tee -a "$CRON_LOG"

    response=$(curl -s -X POST "$url" -d "chat_id=$CHAT_ID" -d "text=$message")

    if echo "$response" | grep -q '"ok":true'; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送成功"| tee -a "$CRON_LOG"
        return 0
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送失败. 响应: $response"| tee -a "$CRON_LOG"
        return 1
    fi
}



# 主任务
main() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 进入主任务" >> "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 参数数量: $#" >> "$CRON_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 所有参数: $@" >> "$CRON_LOG"
    
    check_running
    
if [[ "$*" == *"-cron"* ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') : 检测到-cron参数, 进入cron模式" >> "$CRON_LOG"
    if read_config; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 成功读取配置文件" >> "$CRON_LOG"
        # 继续执行其他操作
        check_and_notify "false"
        
        # 检查是否需要发送每日报告
        current_time=$(TZ='Asia/Shanghai' date +%H:%M)
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 当前时间: $current_time, 设定的报告时间: $DAILY_REPORT_TIME" >> "$CRON_LOG"
        if [ "$current_time" == "$DAILY_REPORT_TIME" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 时间匹配，准备发送每日报告" >> "$CRON_LOG"
            if daily_report; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送成功" >> "$CRON_LOG"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') : 每日报告发送失败" >> "$CRON_LOG"
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') : 当前时间与报告时间不匹配，不发送报告" >> "$CRON_LOG"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') : 配置文件不存在或不完整，跳过检查" >> "$CRON_LOG"
        exit 1
    fi

    else
        # 交互模式
        echo "进入交互模式"
          if ! read_config; then
            echo "需要进行初始化配置。"
            initial_config
        fi
        
        setup_cron
        
# 直接显示当前配置摘要
        echo "当前配置摘要："
        echo "机器名称: $MACHINE_NAME"
        echo "每日报告时间: $DAILY_REPORT_TIME"
        echo "Bot Token: ${BOT_TOKEN:0:10}..." # 只显示前10个字符
        echo "Chat ID: $CHAT_ID"
        
        echo "脚本正在运行中。按 'q' 退出，按 'c' 检查流量，按 'd' 手动发送每日报告，按 'r' 重新加载配置，按 't' 发送测试消息，按 'm' 修改配置，按 'h' 修改每日报告时间。"
        while true; do
            read -n 1 -t 1 input
            if [ -n "$input" ]; then
                echo
                case $input in
                    q|Q) 
                        echo "退出脚本。"
                        exit 0
                        ;;
                    c|C)
                        check_and_notify
                        ;;
                    d|D)
                        daily_report
                        ;;
                    r|R)
                        read_config
                        echo "配置已重新加载。"
                        ;;
                    t|T)
                        test_telegram_notification
                        ;;
                    m|M)
                        initial_config
                        ;;
                    h|H)
                        echo "请输入新的每日报告时间 (HH:MM): "
                        read -r new_time
                        if [[ $new_time =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                            sed -i "s/DAILY_REPORT_TIME=.*/DAILY_REPORT_TIME=$new_time/" "$CONFIG_FILE"
                            echo "每日报告时间已更新为 $new_time"
                        else
                            echo "无效的时间格式。未更改。"
                        fi
                        ;;
                    *)
                        echo "无效的输入: $input"
                        ;;
                esac

                echo "脚本正在运行中。按 'q' 退出，按 'c' 检查流量，按 'd' 手动发送每日报告，按 'r' 重新加载配置，按 't' 发送测试消息，按 'm' 修改配置，按 'h' 修改每日报告时间。"
            fi
        done
    fi
}


# 执行主函数
main "$@"
echo "----------------------------------------------"| tee -a "$CRON_LOG"
