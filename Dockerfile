FROM debian:stable

LABEL "name"="Debian Build"
LABEL "description"=""
LABEL "maintainer"="Kitsune Solar <kitsune.solar@gmail.com>"
LABEL "repository"="https://github.com/ghastore/debian-build.git"
LABEL "homepage"="https://github.com/ghastore"

RUN apt update && apt install --yes ca-certificates

COPY sources-list /etc/apt/sources.list
COPY *.sh /
RUN apt update && apt install --yes bash curl git git-lfs tar xz-utils build-essential fakeroot devscripts

ENTRYPOINT ["/entrypoint.sh"]
