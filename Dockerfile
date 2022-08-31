FROM debian:stable

LABEL "name"="Debian Build Package"
LABEL "description"=""
LABEL "maintainer"="z17 CX <mail@z17.cx>"
LABEL "repository"="https://github.com/pkgstore/github-action-build-deb.git"
LABEL "homepage"="https://pkgstore.github.io/"

RUN apt update && apt install --yes ca-certificates

COPY sources-list /etc/apt/sources.list
COPY *.sh /
RUN apt update && apt install --yes bash curl git git-lfs tar xz-utils build-essential fakeroot devscripts

ENTRYPOINT ["/entrypoint.sh"]
