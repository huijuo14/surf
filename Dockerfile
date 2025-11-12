FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install ALL required libraries + VPN tools
RUN apt-get update && apt-get install -y \
    wget curl xvfb python3 python3-pip unzip dbus openvpn \
    libdbus-1-3 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libgbm1 libasound2 libx11-6 libxext6 libxi6 \
    libxtst6 libxss1 libxcb1 libcairo2 libpango-1.0-0 \
    libpangocairo-1.0-0 libgdk-pixbuf2.0-0 libglib2.0-0 \
    libgtk-3-0 libnotify4 net-tools iproute2 iptables resolvconf \
    && rm -rf /var/lib/apt/lists/*

# Install Python requests
RUN pip3 install requests

WORKDIR /app

# Download FeelingSurf
RUN wget -q https://github.com/feelingsurf/viewer/releases/download/2.5.0/FeelingSurfViewer-linux-x64-2.5.0.zip && \
    unzip -q FeelingSurfViewer-linux-x64-2.5.0.zip && \
    rm FeelingSurfViewer-linux-x64-2.5.0.zip && \
    chmod +x FeelingSurfViewer

# Create Python script to get REAL VPN config
RUN echo 'import requests\nimport base64\nimport random\n\n# Get VPNGate server list\ntry:\n    url = "http://www.vpngate.net/api/iphone/"\n    response = requests.get(url, timeout=10)\n    lines = response.text.split("\\n")\n    \n    working_configs = []\n    for line in lines[2:]:\n        if line and "," in line:\n            parts = line.split(",")\n            if len(parts) > 14 and parts[1] != "*" and parts[14]:\n                config_b64 = parts[14]\n                try:\n                    config = base64.b64decode(config_b64).decode("utf-8")\n                    # Check if it'\''s a valid OpenVPN config\n                    if "remote " in config and "client" in config and "dev " in config:\n                        # Fix the config - remove HTML if present\n                        if "<!DOCTYPE" not in config:\n                            working_configs.append((parts[1], config))\n                except:\n                    continue\n    \n    if working_configs:\n        # Pick a random working config\n        ip, config = random.choice(working_configs)\n        with open("/tmp/vpn.ovpn", "w") as f:\n            f.write(config)\n        print(f"Using VPN: {ip}")\n        exit(0)\n    else:\n        print("No valid VPN configs found")\n        exit(1)\n        \nexcept Exception as e:\n    print(f"Error: {e}")\n    exit(1)' > /app/find_vpn.py

# Create startup script with WORKING VPN
RUN echo '#!/bin/bash\n\necho "=== VPN Setup === "\n\n# Function to check current IP\ncheck_ip() {\n    curl -s --max-time 10 https://api.ipify.org || echo "Unknown"\n}\n\necho "🌐 Initial IP: $(check_ip)"\nINITIAL_IP=$(check_ip)\n\n# Get working VPN config\necho "Finding VPN server..."\npython3 /app/find_vpn.py\n\nif [ -f "/tmp/vpn.ovpn" ]; then\n    echo "Starting OpenVPN..."\n    \n    # Modify config for proper routing\n    cat >> /tmp/vpn.ovpn << EOF\nscript-security 2\nup /etc/openvpn/update-resolv-conf\ndown /etc/openvpn/update-resolv-conf\nauth-nocache\nEOF\n    \n    # Start OpenVPN in foreground initially to see connection\n    timeout 30 openvpn --config /tmp/vpn.ovpn --daemon --log /tmp/vpn.log\n    \n    # Wait for tun0 interface\n    echo "Waiting for VPN tunnel..."\n    for i in {1..30}; do\n        if ip link show tun0 &>/dev/null; then\n            echo "✅ VPN tunnel established (tun0)"\n            break\n        fi\n        sleep 1\n    done\n    \n    # Verify IP changed\n    sleep 5\n    NEW_IP=$(check_ip)\n    echo "🌐 New IP: $NEW_IP"\n    \n    if [ "$INITIAL_IP" != "$NEW_IP" ] && [ "$NEW_IP" != "Unknown" ]; then\n        echo "✅ VPN is working! IP changed from $INITIAL_IP to $NEW_IP"\n    else\n        echo "⚠️  Warning: IP did not change. VPN may not be routing traffic."\n        echo "VPN Log:"\n        tail -20 /tmp/vpn.log 2>/dev/null || echo "No log available"\n    fi\n    \nelse\n    echo "❌ No VPN config available - continuing without VPN"\nfi\n\necho "=== Starting FeelingSurf === "\n\n# Start services\nservice dbus start\nXvfb :99 -screen 0 1024x768x24 &>/dev/null &\nexport DISPLAY=:99\nsleep 3\n\n# Start FeelingSurf\ncd /app\nwhile true; do\n    echo "Starting FeelingSurf Viewer..."\n    ./FeelingSurfViewer --access-token d6e659ba6b59c9866fba8ff01bc56e04 --no-sandbox --disable-dev-shm-usage --disable-gpu\n    echo "⚠️  Viewer exited. Restarting in 30 seconds..."\n    sleep 30\ndone' > /app/start.sh && chmod +x /app/start.sh

ENV access_token="d6e659ba6b59c9866fba8ff01bc56e04"
ENV DISPLAY=:99

# Run with privileged mode for VPN
CMD ["/app/start.sh"]
