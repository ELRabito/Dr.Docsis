FROM python:3.12-slim

# iperf3 is available in Debian repos for all architectures (amd64, arm64, armhf)
RUN apt-get update && \
    apt-get install -y --no-install-recommends iperf3 && \
    rm -rf /var/lib/apt/lists/*

# Non-root user
RUN groupadd -r drdocsis && useradd -r -g drdocsis -d /app -s /sbin/nologin drdocsis

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY drdocsis.py .
COPY servers.json .

RUN mkdir -p /data && chown drdocsis:drdocsis /data

USER drdocsis

ENV PORT=8780
ENV DATA_DIR=/data
ENV CONTRACT_DOWN_MBIT=250
ENV CONTRACT_UP_MBIT=50
ENV SLA_PERCENT=90
ENV TEST_DURATION=15

EXPOSE 8780

HEALTHCHECK --interval=60s --timeout=5s CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8780/health')"

CMD ["python", "drdocsis.py"]
