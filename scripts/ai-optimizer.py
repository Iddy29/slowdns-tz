#!/usr/bin/env python3
import time
import subprocess
import json
import socket
import threading
from datetime import datetime

class AIDNSOptimizer:
    def __init__(self):
        self.dns_servers = [
            ("1.1.1.1", "Cloudflare Primary"),
            ("1.0.0.1", "Cloudflare Secondary"),
            ("8.8.8.8", "Google Primary"),
            ("8.8.4.4", "Google Secondary"),
            ("208.67.222.222", "OpenDNS Primary"),
            ("208.67.220.220", "OpenDNS Secondary"),
            ("9.9.9.9", "Quad9 Primary"),
            ("149.112.112.112", "Quad9 Secondary"),
            ("94.140.14.14", "AdGuard Primary"),
            ("94.140.15.15", "AdGuard Secondary")
        ]
        self.performance_data = {}
        
    def test_dns_speed(self, dns_server):
        try:
            start = time.time()
            socket.gethostbyname_ex("google.com")
            latency = (time.time() - start) * 1000
            return latency
        except:
            return 9999
    
    def optimize_dns_routes(self):
        print("[AI] Testing DNS servers performance...")
        for server, name in self.dns_servers:
            latency = self.test_dns_speed(server)
            self.performance_data[server] = {
                "name": name,
                "latency": latency,
                "timestamp": datetime.now().isoformat()
            }
        
        # Sort by latency
        sorted_dns = sorted(self.performance_data.items(), key=lambda x: x[1]['latency'])
        
        # Update DNS configuration with fastest servers
        with open('/etc/dnsmasq.d/ai-optimized.conf', 'w') as f:
            f.write("# AI-Optimized DNS Configuration\n")
            f.write(f"# Generated at {datetime.now()}\n\n")
            for i, (server, data) in enumerate(sorted_dns[:5]):
                f.write(f"server={server}  # {data['name']} - {data['latency']:.2f}ms\n")
        
        subprocess.run(['systemctl', 'reload', 'dnsmasq'])
        print(f"[AI] DNS optimized! Fastest server: {sorted_dns[0][1]['name']} ({sorted_dns[0][1]['latency']:.2f}ms)")

if __name__ == "__main__":
    optimizer = AIDNSOptimizer()
    while True:
        optimizer.optimize_dns_routes()
        time.sleep(300)  # Re-optimize every 5 minutes