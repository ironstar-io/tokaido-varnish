FROM tokaido/base:stable
RUN apt-get update  \
    && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \	    
        debian-archive-keyring \
        gnupg \
        procps \        
        supervisor \
    && echo '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d \
    && groupadd -g 1100 varnish  \
    && mkdir -p /tokaido/logs/varnish /var/log/supervisor /var/lib/varnish \
    && curl -L https://packagecloud.io/varnishcache/varnish60/gpgkey | apt-key add - \
    && sh -c 'echo "deb https://packagecloud.io/varnishcache/varnish60/debian/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/varnish.list'  \
    && sh -c 'echo "deb-src https://packagecloud.io/varnishcache/varnish60/debian/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/varnish.list'  \
    && apt-get update \
    && apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
        varnish \
    && curl -sLo /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/2.1.2/yq_linux_amd64 \
	&& echo "af1340121fdd4c7e8ec61b5fdd2237b40205563c6cc174e6bdab89de18fc5b97 /usr/local/bin/yq" | sha256sum -c \
	&& chmod 777 /usr/local/bin/yq
    
COPY config/default.vcl /etc/varnish/default.vcl
COPY config/supervisord.conf /etc/supervisor/supervisord.conf
COPY config/log_format.conf /etc/varnish/log_format.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chown varnish:web /tokaido/logs/varnish -R \
    && chmod 700 /tokaido/logs/varnish \
    && chown varnish:web /etc/varnish -R \
    && chown varnish:web /var/log/supervisor/ /etc/supervisor -R\
    && chown varnish:web /var/lib/varnish \
    && chmod 770 /var/lib/varnish \
    && chown varnish:web /usr/local/bin/entrypoint.sh \
    && chmod 750 /usr/local/bin/entrypoint.sh 

USER varnish
EXPOSE 8081
WORKDIR /tmp
CMD ["/usr/local/bin/entrypoint.sh"]