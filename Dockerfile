FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget curl xvfb python3 python3-pip unzip dbus \
    libdbus-1-3 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
    libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libgbm1 libasound2 libx11-6 libxext6 libxi6 \
    libxtst6 libxss1 libxcb1 libcairo2 libpango-1.0-0 \
    libpangocairo-1.0-0 libgdk-pixbuf2.0-0 libglib2.0-0 \
    libgtk-3-0 libnotify4 tinyproxy \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install requests

WORKDIR /app

# Download FeelingSurf
RUN wget -q https://github.com/feelingsurf/viewer/releases/download/2.5.0/FeelingSurfViewer-linux-x64-2.5.0.zip && \
    unzip -q FeelingSurfViewer-linux-x64-2.5.0.zip && \
    rm FeelingSurfViewer-linux-x64-2.5.0.zip && \
    chmod +x FeelingSurfViewer

# Create proxy configuration script
RUN echo 'import os\nimport sys\n\n# Check for proxy credentials from environment\nPROXY_TYPE = os.getenv("PROXY_TYPE", "webshare")  # webshare, brightdata, or custom\nPROXY_HOST = os.getenv("PROXY_HOST", "")\nPROXY_PORT = os.getenv("PROXY_PORT", "")\nPROXY_USER = os.getenv("PROXY_USER", "")\nPROXY_PASS = os.getenv("PROXY_PASS", "")\n\nif PROXY_TYPE == "brightdata" and not all([PROXY_HOST, PROXY_PORT, PROXY_USER, PROXY_PASS]):\n    print("⚠️  Bright Data proxy credentials not set!")\n    print("Set these Railway env variables:")\n    print("  PROXY_TYPE=brightdata")\n    print("  PROXY_HOST=brd.superproxy.io")\n    print("  PROXY_PORT=22225")\n    print("  PROXY_USER=your-username")\n    print("  PROXY_PASS=your-password")\n    sys.exit(1)\n\nif PROXY_TYPE == "webshare" and not all([PROXY_HOST, PROXY_PORT, PROXY_USER, PROXY_PASS]):\n    print("⚠️  Webshare proxy credentials not set!")\n    print("Get free proxy from: https://www.webshare.io/")\n    print("Set these Railway env variables:")\n    print("  PROXY_TYPE=webshare")\n    print("  PROXY_HOST=proxy.webshare.io")\n    print("  PROXY_PORT=80")\n    print("  PROXY_USER=your-username")\n    print("  PROXY_PASS=your-password")\n    sys.exit(1)\n\n# Configure tinyproxy to forward to upstream proxy\nconfig = f"""User nobody\nGroup nogroup\nPort 8888\nTimeout 600\nDefaultErrorFile "/usr/share/tinyproxy/default.html"\nStatFile "/usr/share/tinyproxy/stats.html"\nLogFile "/tmp/tinyproxy.log"\nLogLevel Info\nPidFile "/tmp/tinyproxy.pid"\nMaxClients 100\nMinSpareServers 5\nMaxSpareServers 20\nStartServers 10\nMaxRequestsPerChild 0\nAllow 127.0.0.1\nAllow ::1\nViaProxyName "tinyproxy"\nDisableViaHeader Yes\n\n# Forward to upstream rotating proxy\nUpstream http {PROXY_HOST}:{PROXY_PORT} "{PROXY_USER}" "{PROXY_PASS}"\nUpstream https {PROXY_HOST}:{PROXY_PORT} "{PROXY_USER}" "{PROXY_PASS}"\n"""\n\nwith open("/etc/tinyproxy/tinyproxy.conf", "w") as f:\n    f.write(config)\n\nprint(f"✅ Proxy configured: {PROXY_TYPE}")\nprint(f"   Forwarding to: {PROXY_HOST}:{PROXY_PORT}")\nsys.exit(0)' > /app/setup_proxy.py

# Create startup script
RUN echo '#!/bin/bash\n\necho "========================================"\necho "   🌊 FeelingSurf with IP Rotation 🌊"\necho "========================================"\necho ""\necho "🌐 Server IP (without proxy): $(curl -s --max-time 5 https://api.ipify.org || echo Unknown)"\necho ""\n\n# Setup proxy\necho "🔧 Configuring proxy..."\nif python3 /app/setup_proxy.py; then\n    # Start tinyproxy\n    tinyproxy -c /etc/tinyproxy/tinyproxy.conf\n    sleep 2\n    \n    # Test proxy\n    echo "🧪 Testing proxy connection..."\n    PROXY_IP=$(curl -s --max-time 10 -x http://127.0.0.1:8888 https://api.ipify.org || echo "Failed")\n    \n    if [ "$PROXY_IP" != "Failed" ]; then\n        echo "✅ Proxy working! New IP: $PROXY_IP"\n        export http_proxy=http://127.0.0.1:8888\n        export https_proxy=http://127.0.0.1:8888\n        export HTTP_PROXY=http://127.0.0.1:8888\n        export HTTPS_PROXY=http://127.0.0.1:8888\n    else\n        echo "❌ Proxy test failed"\n        echo "Check your proxy credentials in Railway env variables"\n        exit 1\n    fi\nelse\n    echo "❌ Proxy setup failed - check Railway environment variables"\n    exit 1\nfi\n\necho ""\necho "=== Starting FeelingSurf ==="\n\n# Start services\nservice dbus start 2>/dev/null\nXvfb :99 -screen 0 1920x1080x24 &>/dev/null &\nexport DISPLAY=:99\nsleep 2\n\necho "🚀 Launching FeelingSurf with proxy..."\necho ""\n\n# Start FeelingSurf\ncd /app\nwhile true; do\n    ./FeelingSurfViewer \\\n        --access-token ${ACCESS_TOKEN:-d6e659ba6b59c9866fba8ff01bc56e04} \\\n        --proxy-server=http://127.0.0.1:8888 \\\n        --no-sandbox \\\n        --disable-dev-shm-usage \\\n        --disable-gpu \\\n        --disable-software-rasterizer\n    \n    EXIT_CODE=$?\n    echo ""\n    echo "⚠️  Process exited with code $EXIT_CODE"\n    echo "🔄 Restarting in 10 seconds..."\n    echo ""\n    sleep 10\ndone' > /app/start.sh && chmod +x /app/start.sh

ENV DISPLAY=:99

CMD ["/app/start.sh"]
