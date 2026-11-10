# syntax=docker/dockerfile:1
#
# Odoo 20.0 Community (LGPL-3) - imagen para SITECO OdooCloud
#
# Toda la configuracion se inyecta por variables de entorno (ODOO_* y PG*),
# no hay odoo.conf dentro de la imagen. Ver .env.example.

# ---------------------------------------------------------------------------
# Etapa 1: compila las dependencias Python en un virtualenv
# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        python3-dev \
        python3-venv \
        libpq-dev \
        libldap2-dev \
        libsasl2-dev \
        libssl-dev \
        libffi-dev \
        libxml2-dev \
        libxslt1-dev \
        libjpeg-dev \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH

COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

# ---------------------------------------------------------------------------
# Etapa 2: imagen final
# ---------------------------------------------------------------------------
FROM ubuntu:24.04

# Liga el paquete GHCR al repositorio (las Actions del repo obtienen acceso de escritura)
LABEL org.opencontainers.image.source="https://github.com/Consultores-Odoo-Colombia/siteco_odoo20ce_devel" \
      org.opencontainers.image.description="Odoo 20.0 Community Edition (LGPL-3) - SITECO" \
      org.opencontainers.image.licenses="LGPL-3.0-only"

ARG TARGETARCH
ARG WKHTMLTOX_VERSION=0.12.6.1-3
# sha256 de wkhtmltox_${WKHTMLTOX_VERSION}.jammy_<arch>.deb (github.com/wkhtmltopdf/packaging)
ARG WKHTMLTOX_SHA256_AMD64=4f723b2691ad8638a9df960e0421d346d7315083e3583a334f33362280ddba15
ARG WKHTMLTOX_SHA256_ARM64=2095f20256661ebf0983b9311168596c9d012666e21a94bc24f304db6ac69ec5

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/opt/odoo \
    PATH=/opt/venv/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        python3 \
        libpq5 \
        libldap2 \
        libsasl2-2 \
        libxml2 \
        libxslt1.1 \
        libjpeg-turbo8 \
        libmagic1 \
        postgresql-client \
        fonts-dejavu-core \
        fonts-liberation \
    && curl -fsSL -o /tmp/wkhtmltox.deb \
        "https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOX_VERSION}/wkhtmltox_${WKHTMLTOX_VERSION}.jammy_${TARGETARCH}.deb" \
    && case "${TARGETARCH}" in \
        amd64) WKHTMLTOX_SHA256="${WKHTMLTOX_SHA256_AMD64}" ;; \
        arm64) WKHTMLTOX_SHA256="${WKHTMLTOX_SHA256_ARM64}" ;; \
        *) echo "arquitectura no soportada: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && echo "${WKHTMLTOX_SHA256}  /tmp/wkhtmltox.deb" | sha256sum -c - \
    && apt-get install -y --no-install-recommends /tmp/wkhtmltox.deb \
    && rm -rf /tmp/wkhtmltox.deb /var/lib/apt/lists/*

# Usuario sin privilegios con UID/GID fijos (necesario para permisos de volumenes)
RUN groupadd --gid 10001 odoo \
    && useradd --uid 10001 --gid odoo --home-dir /var/lib/odoo --shell /usr/sbin/nologin odoo \
    && mkdir -p /var/lib/odoo /mnt/extra-addons \
    && chown odoo:odoo /var/lib/odoo /mnt/extra-addons

COPY --from=builder /opt/venv /opt/venv

# Codigo fuente: propiedad de root y solo lectura para el proceso de Odoo
COPY LICENSE /opt/odoo/LICENSE
COPY odoo /opt/odoo/odoo

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && printf '#!/bin/sh\nexec python3 -m odoo "$@"\n' > /usr/local/bin/odoo \
    && chmod 0755 /usr/local/bin/odoo

# Valores por defecto; se sobreescriben en tiempo de ejecucion
ENV ODOO_DATA_DIR=/var/lib/odoo \
    ODOO_ADDONS_PATH=/mnt/extra-addons \
    ODOO_HTTP_INTERFACE=0.0.0.0

VOLUME ["/var/lib/odoo", "/mnt/extra-addons"]
EXPOSE 8069 8072

USER odoo
WORKDIR /var/lib/odoo

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 \
    CMD curl -fsS http://127.0.0.1:8069/web/health || exit 1

ENTRYPOINT ["entrypoint.sh"]
CMD ["odoo"]
