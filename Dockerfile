FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install required libraries (removed VPN tools)
RUN apt-get update && apt-get install -y \
    wget curl xvfb python3 python3-pip unzip dbus \
    libdbus-1-3 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libgbm1 libasound2 libx11-6 libxext6 libxi6 \
    libxtst6 libxss1 libxcb1 libcairo2 libpango-1.0-0 \
    libpangocairo-1.0-0 libgdk-pixbuf2.0-0 libglib2.0-0 \
    libgtk-3-0 libnotify4 proxychains-ng \
    && rm -rf /var/lib/apt/lists/*

# Install Python requests
RUN pip3 install requests

WORKDIR /app

# Download FeelingSurf
RUN wget -q https://github.com/feelingsurf/viewer/releases/download/2.5.0/FeelingSurfViewer-linux-x64-2.5.0.zip && \
    unzip -q FeelingSurfViewer-linux-x64-2.5.0.zip && \
    rm FeelingSurfViewer-linux-x64-2.5.0.zip && \
    chmod +x FeelingSurfViewer

# Create Python script to get free proxy
RUN echo 'import requests\nimport random\n\ntry:\n    # Get free proxy list\n    url = "https://api.proxyscrape.com/v2/?request=get&protocol=http&timeout=10000&country=all&ssl=all&anonymity=all"\n    response = requests.get(url, timeout=10)\n    proxies = [p.strip() for p in response.text.split("\\n") if p.strip()]\n    \n    if proxies:\n        proxy = random.choice(proxies)\n        print(f"Using proxy: {proxy}")\n        \n        # Configure proxychains\n        with open("/etc/proxychains4.conf", "w") as f:\n            f.write("""strict_chain\nproxy_dns\ntcp_read_time_out 15000\ntcp_connect_time_out 8000\n[ProxyList]\nhttp """ + proxy.replace(":", " ") + """\n""")\n        \n        # Test proxy\n        test_response = requests.get("https://api.ipify.org", \n                                    proxies={"http": f"http://{proxy}", "https": f"http://{proxy}"}, \n                                    timeout=10)\n        print(f"Proxy IP: {test_response.text}")\n        exit(0)\n    else:\n        print("No proxies found")\n        exit(1)\nexcept Exception as e:\n    print(f"Proxy setup failed: {e}")\n    print("Continuing without proxy...")\n    exit(1)' > /app/setup_proxy.py

# Create startup script for Railway
RUN echo '#!/bin/bash\n\necho "=== Railway FeelingSurf Setup ==="\necho "🌐 Initial IP: $(curl -s --max-time 5 https://api.ipify.org || echo Unknown)"\n\n# Try to setup proxy (optional - won'\''t break if it fails)\necho "Attempting proxy setup..."\npython3 /app/setup_proxy.py || echo "⚠️  Running without proxy"\n\necho "=== Starting FeelingSurf ==="\n\n# Start services\nservice dbus start 2>/dev/null || true\nXvfb :99 -screen 0 1024x768x24 &>/dev/null &\nexport DISPLAY=:99\nsleep 3\n\necho "✅ Services started"\necho "🚀 Launching FeelingSurf Viewer..."\necho ""\n\n# Start FeelingSurf\ncd /app\nwhile true; do\n    ./FeelingSurfViewer \\\n        --access-token d6e659ba6b59c9866fba8ff01bc56e04 \\\n        --no-sandbox \\\n        --disable-dev-shm-usage \\\n        --disable-gpu \\\n        --disable-software-rasterizer \\\n        2>&1 | grep -E "INFO|ERROR|Starting|authenticated|Loading"\n    \n    echo ""\n    echo "⚠️  Viewer stopped. Restarting in 30s..."\n    sleep 30\ndone' > /app/start.sh && chmod +x /app/start.sh

ENV DISPLAY=:99

CMD ["/app/start.sh"]
