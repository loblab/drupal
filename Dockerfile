# https://github.com/docker-library/drupal/blob/master/8.4/apache/Dockerfile
FROM drupal:8-apache
MAINTAINER loblab

ENV WWW_ROOT /var/www/html
ENV PHP_MODULES geshi/geshi michelf/php-markdown
ENV USER_NAME loblab
ENV USER_ID 1000

RUN echo "Update system & install system packages..." \
    && apt-get update \
    && apt-get -y upgrade \
    && apt-get -y install sudo

RUN echo "Create user ${USER_NAME} who can sudo without password..." \
    && useradd -m -u ${USER_ID} ${USER_NAME} \
    && adduser ${USER_NAME} sudo \
    && echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

RUN echo "Install PHP composer..." \
    && php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php -r "if (hash_file('SHA384', 'composer-setup.php') === '544e09ee996cdf60ece3804abc52599c22b1f40f4323403c44d44fdfdd586475ca9813a858088ffbc1f233e9b180f061') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" \
    && php composer-setup.php \
    && php -r "unlink('composer-setup.php');" \
    && mv composer.phar /usr/local/bin/composer

RUN echo "Install drush..." \
    && php -r "readfile('http://files.drush.org/drush.phar');" > drush \
    && chmod +x drush \
    && mv drush /usr/local/bin \
    && drush -y init

RUN echo "Install PHP modules..." \
    && cd ${WWW_ROOT} \
    && chown ${USER_NAME}:${USER_NAME} composer.* \
    && chown -R ${USER_NAME}:${USER_NAME} vendor \
    && sudo -u ${USER_NAME} composer install \
    && sudo -u ${USER_NAME} composer require ${PHP_MODULES}

