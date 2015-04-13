# Copyright (c) 2015, Fletcher Nichol
# All rights reserved.
# Source: https://github.com/fnichol/openbsd-builder

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:

# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.

# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set -eu
test "x${DEBUG_SCRIPT}" != "x" && set -x

banner() {
  echo "---> ${1}"
}

build_kernel() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if test ! -f "${cookie_dir}/.kernel_built"; then
    banner "Building kernel"
    (cd "/usr/src/sys/arch/${ARCH}/conf"; \
      config GENERIC; \
      cd ../compile/GENERIC; \
      make clean; \
      make; \
      make install
    )
    (cd "/usr/src/sys/arch/${ARCH}/conf"; \
      config GENERIC.MP; \
      cd ../compile/GENERIC.MP; \
      make clean; \
      make; \
      make install
    )
    touch "${cookie_dir}/.kernel_built"
    banner "System must reboot for new kernel to load."
    info "Run 'vagrant reload' and re-run this program to continue"
    touch "${FINAL_RELEASEDIR}/.reboot_required"
    exit
  fi
}

build_userland() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if test ! -f "${cookie_dir}/.userland_built"; then
    banner "Building userland"
    rm -rf /usr/obj/*
    (cd /usr/src; make obj)
    (cd /usr/src/etc; env DESTDIR=/ make distrib-dirs)
    (cd /usr/src; make build)
    touch "${cookie_dir}/.userland_built"
  fi
}

build_xenocara() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if test ! -f "${cookie_dir}/.xenocara_built"; then
    banner "Building xenocara"
    rm -rf /usr/xobj/*
    (cd /usr/xenocara; \
      make bootstrap; \
      make obj; \
      make build
    )
    touch "${cookie_dir}/.xenocara_built"
  fi
}

combine_sha256() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if (cd "$FINAL_RELEASEDIR"; test -f SHA256.release && test -f SHA256.xenocara); then
    banner "Combining SHA256 entries"
    (cd "${FINAL_RELEASEDIR}"; \
      cat SHA256.release SHA256.xenocara | sort > SHA256; \
      rm -f SHA256.release SHA256.xenocara
    )
  fi
}

create_index() {
  banner "Creating index"
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  (cd "$FINAL_RELEASEDIR"; ls -nT >index.txt)
}

do_download() {
  sigfile="`dirname $2`/SHA256.sig"

  if test ! -f "$sigfile"; then
    info "Downloading ${MIRROR}/`basename $sigfile` to ${sigfile}"
    ftp -o "$sigfile" "${MIRROR}/`basename $sigfile`"
  fi

  if test -f "$2"; then
    info "File ${2} exists, skipping download"
  else
    info "Downloading ${MIRROR}/${1} to ${2}"
    ftp -o "$2" "${MIRROR}/${1}"
  fi

  info "Verifying ${2}"
  (cd "`dirname $2`"; signify -C \
    -p "/etc/signify/openbsd-`uname -r | sed 's/\.//'`-base.pub" \
    -x "$sigfile" "`basename $2`"
  )
}

download_sources() {
  banner "Downloading sources"
  test "x${DEBUG_SCRIPT}" = "x" && set -eu || set -eux

  do_download "src.tar.gz" "${dl_dir}/src.tar.gz"
  do_download "sys.tar.gz" "${dl_dir}/sys.tar.gz"
  do_download "xenocara.tar.gz" "${dl_dir}/xenocara.tar.gz"
  do_download "ports.tar.gz" "${dl_dir}/ports.tar.gz"
}

extract_sources() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if test ! -f "/usr/src/sys/Makefile"; then
    banner "Preloading sys tree"
    tar xhzf "${dl_dir}/sys.tar.gz" -C "/usr/src"
  else
    info "sys tree extracted, skipping"
  fi
  if test ! -f "/usr/src/Makefile"; then
    banner "Preloading src tree"
    tar xhzf "${dl_dir}/src.tar.gz" -C "/usr/src"
  else
    info "src tree extracted, skipping"
  fi
  if test ! -f "/usr/xenocara/Makefile"; then
    banner "Preloading xenocara tree"
    tar xhzf "${dl_dir}/xenocara.tar.gz" -C "/usr"
  else
    info "xenocara tree extracted, skipping"
  fi
  if test ! -f "/usr/ports/Makefile"; then
    banner "Preloading ports tree"
    tar xhzf "${dl_dir}/ports.tar.gz" -C "/usr"
  else
    info "ports tree extracted, skipping"
  fi
}

info() {
  echo "   > ${1}"
}

install_signify_key() {
  banner "Installing `basename $signify_key_pub_file` into source tree"
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  cp -p "$signify_key_pub_file" \
    "/usr/src/etc/signify/openbsd-`uname -r | sed 's/\.//'`-base.pub"
}

mount_ramdisk() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if ! (mount | grep "${1} type mfs" 2>&1 >/dev/null); then
    banner "Mounting ${2} RAMDISK for ${1}"
    mount_mfs -s "$2" -o async,nosuid,nodev /dev/sd0b "$1"
  fi
}

prep_cvs_host() {
  ssh_config="${HOME}/.ssh/config"
  if test ! -f "$ssh_config" || grep "Match User anoncvs" "$ssh_config" 2>&1 >/dev/null; then
    mkdir -p "`dirname $ssh_config`"
    chmod 0500 "`dirname $ssh_config`"
    echo "Match User anoncvs" >> "$ssh_config"
    echo "StrictHostKeyChecking no" >> "$ssh_config"
  fi
}

prep_directories() {
  banner "Preparing directories"
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  mkdir -p "$BUILDDIR" "$cookie_dir" "$dl_dir" /home/{ports,xenocara}

  ln -snf /home/xenocara /usr/xenocara
  ln -snf /home/ports /usr/ports
}

prep_signify_files() {
  mkdir -p "`dirname $signify_key_pub_file`"
  echo "$SIGNIFY_KEY_PUB" >"$signify_key_pub_file"
  unset SIGNIFY_KEY_PUB
  chmod 644 "$signify_key_pub_file"

  mkdir -p "`dirname $signify_key_sec_file`"
  echo "$SIGNIFY_KEY_SEC" >"$signify_key_sec_file"
  unset SIGNIFY_KEY_SEC
  chmod 400 "$signify_key_sec_file"
}

release_system() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if test ! -f "${cookie_dir}/.system_release_built"; then
    banner "Building release"

    if test -d ${FINAL_DESTDIR}; then
      info "Clearing out ${FINAL_DESTDIR}"
      mv ${FINAL_DESTDIR} ${FINAL_DESTDIR}.old
      rm -rf ${FINAL_DESTDIR}.old &
    fi

    mkdir -p ${FINAL_DESTDIR} ${FINAL_RELEASEDIR}
    (cd /usr/src/etc; \
      env DESTDIR=${FINAL_DESTDIR} RELEASEDIR=${FINAL_RELEASEDIR} make release
    )

    banner "Checking release"
    (cd /usr/src/distrib/sets; \
      env DESTDIR=${FINAL_DESTDIR} RELEASEDIR=${FINAL_RELEASEDIR} sh checkflist
    )

    cp "${FINAL_RELEASEDIR}/SHA256" "${FINAL_RELEASEDIR}/SHA256.release"

    touch "${cookie_dir}/.system_release_built"
  fi
}

release_xenocara() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if test ! -f "${cookie_dir}/.xenocara_release_built"; then
    banner "Building xenocara release"

    if test -d ${FINAL_DESTDIR}-xencara; then
      info "Clearing out ${FINAL_DESTDIR}-xenocara"
      mv ${FINAL_DESTDIR}-xenocara ${FINAL_DESTDIR}-xenocara.old
      rm -rf ${FINAL_DESTDIR}-xenocara.old &
    fi

    mkdir -p ${FINAL_DESTDIR}-xenocara ${FINAL_RELEASEDIR}
    (cd /usr/xenocara; \
      env DESTDIR=${FINAL_DESTDIR}-xenocara RELEASEDIR=${FINAL_RELEASEDIR} make release
    )

    cp "${FINAL_RELEASEDIR}/SHA256" "${FINAL_RELEASEDIR}/SHA256.xenocara"

    touch "${cookie_dir}/.xenocara_release_built"
  fi
}

show_environment() {
  banner "Environment:"
  env | sort
}

sign_sha256() {
  banner "Signing SHA256"
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  (cd "${FINAL_RELEASEDIR}"; \
    signify -S -s "$signify_key_sec_file" -m SHA256 -e -x SHA256.sig
  )
}

unmount_ramdisk() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if (mount | grep "${1} type mfs" 2>&1 >/dev/null); then
    banner "Un-mounting RAMDISK for ${1}"
    umount "$1"
  fi
}

update_sources() {
  test "x${DEBUG_SCRIPT}" != "x" && set -x

  if test ! -f "${cookie_dir}/.cvs_src_updated"; then
    banner "Updating src tree to ${CVS_TAG}"
    (cd /usr; cvs -q -d${CVSROOT} update -r${CVS_TAG} -P src)
    touch "${cookie_dir}/.cvs_src_updated"
  else
    info "src tree updated, skipping"
  fi
  if test ! -f "${cookie_dir}/.cvs_ports_updated"; then
    banner "Updating ports tree to ${CVS_TAG}"
    (cd /usr; cvs -q -d${CVSROOT} update -r${CVS_TAG} -P ports)
    touch "${cookie_dir}/.cvs_ports_updated"
  else
    info "ports tree updated, skipping"
  fi
  if test ! -f "${cookie_dir}/.cvs_xenocara_updated"; then
    banner "Updating xenocara tree to ${CVS_TAG}"
    (cd /usr; cvs -q -d${CVSROOT} update -r${CVS_TAG} -P xenocara)
    touch "${cookie_dir}/.cvs_xenocara_updated"
  else
    info "xenocara tree updated, skipping"
  fi
}


##############################
# Program begins

cookie_dir="${BUILDDIR}/cookies"
dl_dir="${BUILDDIR}/downloads"
signify_key_pub_file="${BUILDDIR}/signify/openbsd-`uname -r | sed 's/\.//'`-stable-base.pub"
signify_key_sec_file="${BUILDDIR}/signify/openbsd-`uname -r | sed 's/\.//'`-stable-base.sec"

prep_signify_files

banner "Build started at `date +%FT%T%z`"
show_environment

prep_directories
download_sources
prep_cvs_host
extract_sources
update_sources
install_signify_key

build_kernel

mount_ramdisk "/usr/obj" "1G"
build_userland
release_system
unmount_ramdisk "/usr/obj"

mount_ramdisk "/usr/xobj" "1G"
build_xenocara
release_xenocara
unmount_ramdisk "/usr/xobj"

combine_sha256
sign_sha256
create_index
