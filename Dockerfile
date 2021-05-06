ARG ALPINE_ARCH=arm32v7

FROM ${ALPINE_ARCH}/alpine:3

WORKDIR /usr/local/bin

RUN apk add --no-cache openssh curl jq

COPY balena.sh ./

CMD ["balena.sh"]