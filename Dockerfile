ARG NGINX_VERSION=1.21.4 
# https://seankhliao.com/blog/12021-08-24-renovatebot-regex-custom-versioning/

FROM jakoberpf/zerotier-client:1.10.6
LABEL maintainer="github@jakoberpf.de"

RUN apt-get update \
    && apt-get install -y nginx jq curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY nginx.conf /etc/nginx/nginx.conf
COPY default.html /var/www/html/index.html

EXPOSE 80

ADD entrypoint.sh /entrypoint.sh
