ARG NGINX_VERSION=1.21.4

FROM zerotier/zerotier:1.10.6

LABEL maintainer="contact@jakoberpf.de"

RUN apt-get update \
    && apt-get install -y nginx jq curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && echo "daemon off;" >> /etc/nginx/nginx.conf

COPY nginx.conf /etc/nginx/nginx.conf
COPY passthrough.conf /etc/nginx/passthrough.conf

ADD entrypoint.sh /entrypoint.sh
