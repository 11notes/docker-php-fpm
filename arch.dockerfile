# ╔═════════════════════════════════════════════════════╗
# ║                       SETUP                         ║
# ╚═════════════════════════════════════════════════════╝
# GLOBAL
  ARG APP_UID=1000 \
      APP_GID=1000 \
      APP_VERSION=0 \
      APP_ROOT=""

# :: FOREIGN IMAGES
  FROM 11notes/util AS util
  FROM 11notes/util:bin AS util-bin
  FROM 11notes/distroless AS distroless
  FROM 11notes/nginx:full-stable AS distroless-nginx
  FROM 11notes/distroless:tini-pm AS distroless-tini-pm
  FROM 11notes/distroless:localhealth AS distroless-localhealth

# ╔═════════════════════════════════════════════════════╗
# ║                       BUILD                         ║
# ╚═════════════════════════════════════════════════════╝
# :: PHP
  FROM 11notes/alpine:stable AS build
  COPY --from=util-bin / /
  USER root

  RUN set -ex; \
    PHP_VERSION=$(echo "${APP_VERSION}" | awk -F '.' '{print $1$2}'); \
    apk --update --no-cache add \
      php${PHP_VERSION}=~${APP_VERSION} \
      php${PHP_VERSION}-fpm=~${APP_VERSION}; \
    /usr/local/bin/ds /usr/bin/php${PHP_VERSION} \
    /usr/local/bin/ds /usr/sbin/php-fpm${PHP_VERSION}; \
    mv /etc/php${PHP_VERSION} /etc/php; \
    mv /usr/bin/php${PHP_VERSION} /usr/bin/php; \
    mv /usr/sbin/php-fpm${PHP_VERSION} /usr/sbin/php-fpm;

  RUN set -ex; \
    PHP_VERSION=$(echo "${APP_VERSION}" | awk -F '.' '{print $1$2}'); \
    sed -i 's|include=/etc/php'${PHP_VERSION}'|include=/php/etc|' /etc/php/php-fpm.conf; \
    sed -i 's|;error_log = log/php'${PHP_VERSION}'/error.log|error_log = /php/run/php-fpm.log|' /etc/php/php-fpm.conf; \
    sed -i 's|;error_log = syslog|error_log = /php/run/php.log|' /etc/php/php.ini; \
    echo "${PHP_VERSION}" > /etc/php/version_alpine;

  RUN set -ex; \
    rm -rf /usr/local/bin/*;


# :: FILE SYSTEM
  FROM alpine AS file-system
  COPY --from=util / /
  COPY --from=build /etc/php /distroless${APP_ROOT}/etc

  RUN set -ex; \
    PHP_VERSION=$(echo "${APP_VERSION}" | awk -F '.' '{print $1$2}'); \
    eleven mkdir /distroless${APP_ROOT}/{etc,var,run};


# ╔═════════════════════════════════════════════════════╗
# ║                       IMAGE                         ║
# ╚═════════════════════════════════════════════════════╝
# :: HEADER
  FROM scratch

  # :: default arguments
    ARG TARGETPLATFORM \
        TARGETOS \
        TARGETARCH \
        TARGETVARIANT \
        APP_IMAGE \
        APP_NAME \
        APP_VERSION \
        APP_ROOT \
        APP_UID \
        APP_GID \
        APP_NO_CACHE

  # :: default environment
    ENV APP_IMAGE=${APP_IMAGE} \
      APP_NAME=${APP_NAME} \
      APP_VERSION=${APP_VERSION} \
      APP_ROOT=${APP_ROOT}

  # :: multi-stage
    COPY --from=distroless / /
    COPY --from=distroless-nginx / /
    COPY --from=distroless-tini-pm / /
    COPY --from=distroless-localhealth / /
    COPY --from=build / /
    COPY ./rootfs/ /
    COPY --from=file-system --chown=${APP_UID}:${APP_GID} /distroless/ /

# :: PERSISTENT DATA
  VOLUME ["${APP_ROOT}/etc", "${APP_ROOT}/var"]

# :: MONITORING
  HEALTHCHECK --interval=5s --timeout=2s --start-period=5s \
    CMD ["/usr/local/bin/localhealth", "http://127.0.0.1:3000/ping", "-I"]

# :: EXECUTE
  USER ${APP_UID}:${APP_GID}
  ENTRYPOINT ["/usr/local/bin/tini-pm"]