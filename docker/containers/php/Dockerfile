FROM php:7.4-fpm-alpine

RUN mkdir -p /var/run/mysqld
RUN mkdir -p /run/php

ARG APP_ENV='prod'
ARG APP_ENV=${APP_ENV}
ENV APP_ENV=${APP_ENV}

ARG USER_ID='1000'
ARG USER_ID=${USER_ID}
ENV USER_ID=${USER_ID}

ARG GROUP_ID='1000'
ARG GROUP_ID=${GROUP_ID}
ENV GROUP_ID=${GROUP_ID}

ARG PROJECT_PREFIX='web'
ARG PROJECT_PREFIX=${PROJECT_PREFIX}
ENV PROJECT_PREFIX=${PROJECT_PREFIX}

RUN apk add ssmtp bash vim

RUN cd /bin && curl --silent --show-error https://getcomposer.org/installer | php && mv composer.phar composer && chmod 777 composer

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions openssl pdo_mysql mbstring tokenizer xml mysqli gd zip

#ADD ./conf/php.ini /etc/php/8.2/fpm/php.ini
#ADD ./conf/php.ini /etc/php/8.2/cli/php.ini
#ADD ./conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
#COPY ./conf/ssmtp.conf /etc/ssmtp/ssmtp.conf

ADD ./conf/php.ini /usr/local/etc/php/php.ini

RUN sed -i -e "s/www-data:x:82:82:Linux User,,,:\/home\/www-data:\/sbin\/nologin/www-data:x:${USER_ID}:${GROUP_ID}:Linux User,,,:\/home\/www-data:\/bin\/bash/g" /etc/passwd
RUN sed -i -e "s/www-data:x:82:www-data/www-data:x:${GROUP_ID}:www-data/g" /etc/group

WORKDIR /var/www/html
RUN export HOME="/var/www/html"

EXPOSE 9000
