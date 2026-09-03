#!/bin/bash

declare -A servers


while getopts "c:e:" opt; do
  case $opt in
    c) path="$OPTARG" ;;
    e) EMAIL_RECIPIENT="$OPTARG" ;;
    *) echo "Usage: $0 -c <config_file> -e <email>" ; exit 1 ;;
  esac
done

if [[ -z "$path" || -z "$EMAIL_RECIPIENT" ]]; then
    echo "Error: Both -c (config file) and -e (email) are required."
    echo "Usage: $0 -c /path/to/servers.csv -e user@example.com"
    exit 1
fi

d=$(date +'%y-%m-%d__%H-%M')
LOG_DIR="$(pwd)"
MAIN_LOG="${LOG_DIR}/${d}_LOGS"
FAILED_LOG="${LOG_DIR}/${d}_FAILED_LOGS"


get_key() {
        while IFS=',' read -r col1 col2 col3 || [ -n "$col1" ]; do
        servers["$col1"@"$col2"]="$col3"
    done < <(tr -d '\r' < "$path")
}
get_key

server_check() {
    local target_name="$1"
    local target_key="${servers["$target_name"]}"

    ssh -T -i "$target_key" "$target_name" 'bash -s' << 'EOF'
        RAM_WARN=75
        RAM_CRIT=90
        DISK_WARN=80
        DISK_CRIT=90

        mem_pct=$(free | awk '/Mem:/ {printf "%d", $3/$2 * 100}')
        mem_avail=$(free -m | awk '/Mem:/ {print $7}')

        if [[ "$mem_pct" -ge "$RAM_CRIT" ]]; then
            mem_status="[CRITICAL] ${mem_pct}% used (${mem_avail}MB available)"
        elif [[ "$mem_pct" -ge "$RAM_WARN" ]]; then
            mem_status="[WARNING] ${mem_pct}% used (${mem_avail}MB available)"
        else
            mem_status="[OK] ${mem_pct}% used (${mem_avail}MB available)"
        fi

        disk_pct=$(df / | awk 'NR==2 {printf "%d", $3/$2 * 100}')
        disk_free=$(df -h / | awk 'NR==2 {print $4}')

        if [[ "$disk_pct" -ge "$DISK_CRIT" ]]; then
            disk_status="[CRITICAL] ${disk_pct}% used (${disk_free} free)"
        elif [[ "$disk_pct" -ge "$DISK_WARN" ]]; then
            disk_status="[WARNING] ${disk_pct}% used (${disk_free} free)"
        else
            disk_status="[OK] ${disk_pct}% used (${disk_free} free)"
        fi

        load_avg=$(awk '{printf "%s (1m), %s (5m), %s (15m)", $1, $2, $3}' /proc/loadavg)
        sys_uptime=$(uptime -p 2>/dev/null || uptime | sed 's/.*up //' | cut -d, -f1)
        docker_cnt="$(sudo docker ps -q 2>/dev/null | wc -l) running / $(sudo docker ps -aq 2>/dev/null | wc -l) total"

        printf "  %-18s : %s\n" "Load Average"     "$load_avg"
        printf "  %-18s : %s\n" "Uptime"           "$sys_uptime"
        printf "  %-18s : %s\n" "Memory"           "$mem_status"
        printf "  %-18s : %s\n" "Storage (/)"      "$disk_status"
        printf "  %-18s : %s\n" "Docker Status"    "$docker_cnt"
EOF
}

report() {
    local server_target="$1"
    local report_data="$2"
    
    {
        echo "==================================================================="
        printf "  SERVER  : %s\n" "$server_target"
        echo "==================================================================="
        echo "$report_data"
        echo -e "\n\n" 
    } >> "$MAIN_LOG"
}

failed_logs() {
    echo " Connection to $1 failed due to: $2" >> "$FAILED_LOG"
    echo "==========================================" >> "$FAILED_LOG"
}


for i in "${!servers[@]}"; do 
    echo "Trying to connect to $i..."
   
    check=$(ssh -i "${servers["$i"]}" -o BatchMode=yes -o ConnectTimeout=5 "$i" exit 2>&1)
    
    if [[ $? -eq 0 ]]; then  
        echo "Connected successfully to $i"
        r=$(server_check "$i")
        report "$i" "$r" 
        echo "Data retrieved successfully at $MAIN_LOG"
        echo "EXITING $i..."
    else
       # echo "$i"
       # echo "${servers["$i"]}"
        echo "Could not connect to $i"
        echo "$check"
        failed_logs "$i" "$check"
        echo "Check $FAILED_LOG for details."
    fi
    echo "======================================================="
done




if [[ -f "$MAIN_LOG" ]]; then
    warning_cnt=$(grep -F -c '[WARNING]' "$MAIN_LOG" || true)
    critical_cnt=$(grep -F -c '[CRITICAL]' "$MAIN_LOG" || true)

    if [[ "$warning_cnt" -gt 0 || "$critical_cnt" -gt 0 ]]; then
        { 
          echo "Subject: [ALERT] Infrastructure Health Checks - $d"
          echo ""
          echo "Summary: Found $critical_cnt CRITICAL and $warning_cnt WARNING issue(s)."
          echo "==================================================================="
          echo ""

          awk -v RS="" '/\[WARNING\]|\[CRITICAL\]/' "$MAIN_LOG"
          
        } | msmtp "$EMAIL_RECIPIENT"
    fi
fi

if [[ -s "$FAILED_LOG" ]]; then 
    { 
      echo "Subject: [FAILED] SSH Connections Report - $d"
      echo ""
      cat "$FAILED_LOG"
    } | msmtp "$EMAIL_RECIPIENT"
fi