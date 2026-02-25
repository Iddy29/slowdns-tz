#!/bin/bash

# A.I SLOWDNS TZ Monitor
LOG_DIR="/opt/ai-slowdns-tz/logs"
CONFIG_DIR="/opt/ai-slowdns-tz/config"

# Function to check and restart services
check_service() {
    local service=$1
    if ! systemctl is-active --quiet $service; then
        echo "[$(date)] Restarting $service..." >> $LOG_DIR/monitor.log
        systemctl restart $service
    fi
}

# Function to optimize DNS performance
optimize_dns() {
    # Get current DNS query statistics
    local queries=$(grep -c "query" $LOG_DIR/dnsmasq.log 2>/dev/null || echo 0)
    local cache_hits=$(grep -c "cached" $LOG_DIR/dnsmasq.log 2>/dev/null || echo 0)
    
    # Calculate cache hit ratio
    if [ $queries -gt 0 ]; then
        local hit_ratio=$(echo "scale=2; $cache_hits * 100 / $queries" | bc)
        echo "[$(date)] Cache hit ratio: $hit_ratio%" >> $LOG_DIR/performance.log
        
        # Adjust cache size if needed
        if (( $(echo "$hit_ratio < 80" | bc -l) )); then
            echo "[$(date)] Increasing cache size for better performance" >> $LOG_DIR/performance.log
            sed -i 's/cache-size=.*/cache-size=100000/' /etc/dnsmasq.conf
            systemctl reload dnsmasq
        fi
    fi
}

# Main monitoring loop
while true; do
    # Check DNSTT server
    if ! pgrep -f "dnstt-server" > /dev/null; then
        cd /opt/ai-slowdns-tz
        screen -dmS ai-slowdns ./dnstt-server -udp :5300 -mtu 1400 -privkey-file server.key NAMESERVER_PLACEHOLDER 127.0.0.1:PORT_PLACEHOLDER
        echo "[$(date)] DNSTT server restarted" >> $LOG_DIR/monitor.log
    fi
    
    # Check critical services
    check_service dnsmasq
    check_service unbound
    check_service redis
    
    # Run DNS optimization
    optimize_dns
    
    # Run Python AI optimizer
    if ! pgrep -f "ai-optimizer.py" > /dev/null; then
        python3 /opt/ai-slowdns-tz/scripts/ai-optimizer.py &
        echo "[$(date)] AI Optimizer restarted" >> $LOG_DIR/monitor.log
    fi
    
    sleep 30
done