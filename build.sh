#!/bin/bash -e

# -------------------------------------------------------------------------------------------------------------------- #
# CONFIGURATION.
# -------------------------------------------------------------------------------------------------------------------- #

# Vars.
GIT_REPO_SRC="${1}"
GIT_REPO_DST="${2}"
GIT_USER="${3}"
GIT_EMAIL="${4}"
GIT_TOKEN="${5}"
OBS_USER="${6}"
OBS_PASSWORD="${7}"
OBS_TOKEN="${8}"
OBS_PROJECT="${9}"
OBS_PACKAGE="${10}"
NAME="$( echo "${GIT_REPO_DST}" | awk -F '[/.]' '{ print $6 }' )"

# Apps.
build="$( command -v dpkg-source )"
curl="$( command -v curl )"
date="$( command -v date )"
git="$( command -v git )"
hash="$( command -v rhash )"
mv="$( command -v mv )"
rm="$( command -v rm )"
sleep="$( command -v sleep )"
tar="$( command -v tar )"
tee="$( command -v tee )"

# Dirs.
d_src="/root/git/src"
d_dst="/root/git/dst"

# Git.
${git} config --global user.name "${GIT_USER}"
${git} config --global user.email "${GIT_EMAIL}"
${git} config --global init.defaultBranch 'main'

# Commands.
cmd_build="${build} -i --build _build/"

# -------------------------------------------------------------------------------------------------------------------- #
# INITIALIZATION.
# -------------------------------------------------------------------------------------------------------------------- #

init() {
  # Functions.
  ts="$( _timestamp )"

  # Run.
  clone \
    && ( ( pack && build && move ) 2>&1 ) | ${tee} "${d_src}/build.log" \
    && sum \
    && push \
    && obs_upload \
    && obs_trigger
}

# -------------------------------------------------------------------------------------------------------------------- #
# GIT: CLONE REPOSITORIES.
# -------------------------------------------------------------------------------------------------------------------- #

clone() {
  echo "--- [GIT] CLONE: ${GIT_REPO_SRC#https://} & ${GIT_REPO_DST#https://}"

  local src="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO_SRC#https://}"
  local dst="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO_DST#https://}"

  ${git} clone "${src}" "${d_src}" \
    && ${git} clone "${dst}" "${d_dst}"

  echo "--- [GIT] LIST: '${d_src}'"
  ls -1 "${d_src}"

  echo "--- [GIT] LIST: '${d_dst}'"
  ls -1 "${d_dst}"
}

# -------------------------------------------------------------------------------------------------------------------- #
# SYSTEM: PACKING "*.ORIG" FILES.
# -------------------------------------------------------------------------------------------------------------------- #

pack() {
  echo "--- [SYSTEM] PACK: '${NAME}' (*.orig.tar.xz)"
  _pushd "${d_src}" || exit 1

  # Set package version.
  local ver="1.0.0"
  for i in "${NAME}-"*; do local ver=${i##*-}; break; done;

  # Check '*.orig.tar.*' file.
  for i in *.orig.tar.*; do
    if [[ -f ${i} ]]; then
      echo "File '${i}' found!"
    else
      echo "File '*.orig.tar.*' not found! Creating..."
      local dir="${NAME}-${ver}"
      local tar="${NAME}_${ver}.orig.tar.xz"
      ${tar} -cJf "${tar}" "${dir}"
      echo "File '${tar}' created!"
    fi
    break
  done

  _popd || exit 1
}

# -------------------------------------------------------------------------------------------------------------------- #
# SYSTEM: BUILD PACKAGE.
# -------------------------------------------------------------------------------------------------------------------- #

build() {
  echo "--- [SYSTEM] BUILD: '${GIT_REPO_SRC#https://}'"
  _pushd "${d_src}" || exit 1

  # Run build.
  ${cmd_build}

  # Check build status.
  for i in *.dsc; do
    if [[ -f ${i} ]]; then
      echo "File '${i}' found!"
      echo "Build completed!"
    else
      echo "File '*.dsc' not found!"
      exit 1
    fi
    break
  done

  _popd || exit 1
}

# -------------------------------------------------------------------------------------------------------------------- #
# SYSTEM: MOVE PACKAGE TO DEBIAN PACKAGE STORE REPOSITORY.
# -------------------------------------------------------------------------------------------------------------------- #

move() {
  echo "--- [SYSTEM] MOVE: '${d_src}' -> '${d_dst}'"

  # Remove old files from 'd_dst'.
  echo "Removing old files from repository..."
  ${rm} -fv "${d_dst}"/*

  # Move new files from 'd_src' to 'd_dst'.
  echo "Moving new files to repository..."
  for i in _service _meta README.md LICENSE *.tar.* *.dsc *.log; do
    ${mv} -fv "${d_src}"/${i} "${d_dst}" || exit 1
  done
}

# -------------------------------------------------------------------------------------------------------------------- #
# SYSTEM: CHECKSUM.
# -------------------------------------------------------------------------------------------------------------------- #

sum() {
  echo "--- [HASH] CHECKSUM FILES"
  _pushd "${d_dst}" || exit 1

  for i in *; do
    echo "Checksum '${i}'..."
    [[ -f "${i}" ]] && ${hash} -u "${NAME}.sha3-256" --sha3-256 "${i}"
  done

  _popd || exit 1
}

# -------------------------------------------------------------------------------------------------------------------- #
# GIT: PUSH PACKAGE TO DEBIAN PACKAGE STORE REPOSITORY.
# -------------------------------------------------------------------------------------------------------------------- #

push() {
  echo "--- [GIT] PUSH: '${d_dst}' -> '${GIT_REPO_DST#https://}'"
  _pushd "${d_dst}" || exit 1

  # Commit build files & push.
  echo "Commit build files & push..."
  ${git} add . \
    && ${git} commit -a -m "BUILD: ${ts}" \
    && ${git} push

  _popd || exit 1
}

# -------------------------------------------------------------------------------------------------------------------- #
# CURL: UPLOAD "_META" & "_SERVICE" FILES TO OBS.
# -------------------------------------------------------------------------------------------------------------------- #

obs_upload() {
  echo "--- [OBS] UPLOAD: '${OBS_PROJECT}/${OBS_PACKAGE}'"

  # Upload '_meta'.
  echo "Uploading '${OBS_PROJECT}/${OBS_PACKAGE}/_meta'..."
  ${curl} -u "${OBS_USER}":"${OBS_PASSWORD}" -X PUT -T \
    "${d_dst}/_meta" "https://api.opensuse.org/source/${OBS_PROJECT}/${OBS_PACKAGE}/_meta"

  # Upload '_service'.
  echo "Uploading '${OBS_PROJECT}/${OBS_PACKAGE}/_service'..."
  ${curl} -u "${OBS_USER}":"${OBS_PASSWORD}" -X PUT -T \
    "${d_dst}/_service" "https://api.opensuse.org/source/${OBS_PROJECT}/${OBS_PACKAGE}/_service"

  ${sleep} 5
}

# -------------------------------------------------------------------------------------------------------------------- #
# CURL: RUN BUILD PACKAGE IN OBS.
# -------------------------------------------------------------------------------------------------------------------- #

obs_trigger() {
  echo "--- [OBS] TRIGGER: '${OBS_PROJECT}/${OBS_PACKAGE}'"
  ${curl} -H "Authorization: Token ${OBS_TOKEN}" -X POST \
    "https://api.opensuse.org/trigger/runservice?project=${OBS_PROJECT}&package=${OBS_PACKAGE}"
}

# -------------------------------------------------------------------------------------------------------------------- #
# ------------------------------------------------< COMMON FUNCTIONS >------------------------------------------------ #
# -------------------------------------------------------------------------------------------------------------------- #

# Pushd.
_pushd() {
  command pushd "$@" > /dev/null || exit 1
}

# Popd.
_popd() {
  command popd > /dev/null || exit 1
}

# Timestamp.
_timestamp() {
  ${date} -u '+%Y-%m-%d %T'
}

# -------------------------------------------------------------------------------------------------------------------- #
# -------------------------------------------------< INIT FUNCTIONS >------------------------------------------------- #
# -------------------------------------------------------------------------------------------------------------------- #

init "$@"; exit 0
