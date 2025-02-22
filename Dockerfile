FROM php:7.4-apache

# install the PHP extensions we need
RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
        curl --fail -o /root/switchaai-apt-source_1.0.0ubuntu1_all.deb --remote-name https://pkg.switch.ch/switchaai/ubuntu/dists/bionic/main/binary-all/misc/switchaai-apt-source_1.0.0ubuntu1_all.deb; \
        apt install -y /root/switchaai-apt-source_1.0.0ubuntu1_all.deb; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libjpeg-dev \
		libpng-dev \
                libfreetype6-dev \
                libzip-dev \
	; \
	\
	docker-php-ext-configure gd --with-freetype --with-jpeg; \
	docker-php-ext-install gd mysqli opcache zip pdo_mysql; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get install -y libapache2-mod-shib2; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*
# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN echo 'opcache.memory_consumption=128' > /usr/local/etc/php/conf.d/opcache-recommended.ini
RUN echo 'opcache.interned_strings_buffer=8' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
RUN echo 'opcache.max_accelerated_files=4000' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
RUN echo 'opcache.revalidate_freq=2' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
RUN echo 'opcache.fast_shutdown=1' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
RUN echo 'opcache.enable_cli=1' >> /usr/local/etc/php/conf.d/opcache-recommended.ini
RUN echo '<Location /Shibboleth.sso>' >> /etc/apache2/conf-available/shib2.conf
RUN echo '  SetHandler shib' >> /etc/apache2/conf-available/shib2.conf
RUN echo '  AuthType None' >> /etc/apache2/conf-available/shib2.conf
RUN echo '  Require all granted' >> /etc/apache2/conf-available/shib2.conf
RUN echo '  RewriteEngine On' >> /etc/apache2/conf-available/shib2.conf
RUN echo '  RewriteRule ^/Shibboleth.sso.* - [L]' >> /etc/apache2/conf-available/shib2.conf
RUN echo '</Location>' >> /etc/apache2/conf-available/shib2.conf
RUN a2enmod rewrite expires shib
RUN a2enconf shib2

VOLUME /var/www/html
VOLUME /etc/shibboleth

ENV WORDPRESS_VERSION 5.0.1
ENV WORDPRESS_SHA1 298bd17feb7b4948e7eb8fa0cde17438a67db19a

RUN cd /etc/shibboleth/ \
    && shib-keygen

RUN set -ex; \
	curl -o wordpress.tar.gz -fSL "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
	echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c -; \
# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
	tar -xzf wordpress.tar.gz -C /usr/src/; \
	rm wordpress.tar.gz; \
	chown -R www-data:www-data /usr/src/wordpress

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
