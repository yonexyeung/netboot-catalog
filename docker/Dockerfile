# NetBoot Catalog — Docker Appliance
# Provides: nbc CLI + dnsmasq (proxyDHCP/TFTP) + nginx (HTTP) + iPXE binaries

FROM debian:bookworm-slim

ARG IPXE_VERSION=1.21.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    dnsmasq \
    nginx-light \
    inotify-tools \
    iproute2 \
    libarchive-tools \
    curl \
    ca-certificates \
    coreutils \
    mount \
    && rm -rf /var/lib/apt/lists/*

# Install yq
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
    -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Download iPXE binaries from official GitHub releases
RUN mkdir -p /srv/tftp && \
    curl -fsSL "https://github.com/ipxe/ipxe/releases/latest/download/ipxeboot.tar.gz" \
      -o /tmp/ipxe.tar.gz && \
    tar -xzf /tmp/ipxe.tar.gz -C /tmp && \
    cp /tmp/ipxeboot/undionly.kpxe /srv/tftp/undionly.kpxe && \
    cp /tmp/ipxeboot/ipxe.efi /srv/tftp/ipxe.efi && \
    rm -rf /tmp/ipxe.tar.gz /tmp/ipxeboot

# Copy project files
COPY scripts/ /opt/nbc/scripts/
COPY adapters/ /opt/nbc/adapters/
COPY templates/ /opt/nbc/templates/
COPY docker/entrypoint.sh /opt/nbc/entrypoint.sh
COPY docker/dnsmasq.conf /etc/dnsmasq.d/nbc.conf
COPY docker/nginx.conf /etc/nginx/sites-enabled/default

RUN chmod +x /opt/nbc/scripts/* /opt/nbc/entrypoint.sh && \
    ln -sf /opt/nbc/scripts/nbc /usr/local/bin/nbc

# Directories
RUN mkdir -p /srv/import /srv/catalog /srv/tftp

ENV ADAPTERS_DIR=/opt/nbc/adapters
ENV CATALOG_DIR=/srv/catalog
# NBC_SERVER_IP and NBC_BASE_URL are auto-detected at runtime if not set

EXPOSE 67/udp 69/udp 80/tcp 4011/udp

VOLUME ["/srv/import", "/srv/catalog"]

ENTRYPOINT ["/opt/nbc/entrypoint.sh"]
