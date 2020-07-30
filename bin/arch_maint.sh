#!/bin/bash

## arch_maint.sh --- Arch Linux maintenance script
#
# Author: Peter Hua
# Version: $Revision: 1.0$
# Keywords: arch linux bash
#
## Commentary:
#
# See https://wiki.archlinux.org/index.php/System_maintenance
#
# Usage: ./arch_maint.sh [-i]
#        yes n | ./arch_maint.sh | tee ${XDG_DATA_HOME}/arch_maint/update.log
#
## Code:
#

BASE_NAME=$(basename $0)
DATA_PATH=${XDG_DATA_HOME}/${BASE_NAME%.sh}
[ -d ${DATA_PATH} ] || mkdir -p ${DATA_PATH}

PACKAGES_INSTALLED=${DATA_PATH}/packages_installed
PACKAGES_ORPHANED=${DATA_PATH}/packages_orphaned
PACKAGES_FOREIGN=${DATA_PATH}/packages_foreign
PACKAGES_DATABASE=${DATA_PATH}/packages_db.tar.xz
PACKAGES_CONFIG=${DATA_PATH}/packages_etc.tar.xz
GHOST_FILES=${DATA_PATH}/ghosted
BROKEN_LINKS=${DATA_PATH}/broken

RSYNC_SOURCE=${WORKSPACE_HOME}
RSYNC_TARGET=${HOME}/.local/mnt/usb1/workspace
MEDIA_SOURCE=${USER_DIRS}
MEDIA_TARGET=${HOME}/.local/mnt/usb2/Media
RSYNC_EXCLUDES=
RSYNC_SSH="-e \"ssh -T -c arcfour -o Compression=no\""
RSYNC_SSH_TARGET=${USER}@aleph0:${WORKSPACE_HOME}
CRYPT_SOURCE=${HOME}/.local/mnt/media/Media
CRYPT_TARGET=${HOME}/.local/mnt/crypt/Media

while read EXCLUDE; do
    if [[ ! -z ${EXCLUDE} ]]; then
        RSYNC_EXCLUDES+="--exclude=${EXCLUDE} "
    fi
done <<EOF
mnt
EOF

NEWS_FEED="https://www.archlinux.org/feeds/news/"
NEWS_FILE=${DATA_PATH}/NEWS

MIRROR_LIST="https://www.archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=4&use_mirror_status=on"
MIRROR_FILE=${DATA_PATH}/MIRRORS

UPDATE_SCRIPT=${DATA_PATH}/update.sh
echo -e "#!/bin/bash\n" > ${UPDATE_SCRIPT} && chmod u+x ${UPDATE_SCRIPT}

NORMAL="\e[0;0m"
HILITE="\e[0;36m"
PROMPT="\e[0;33m"

hilite() {
    local MESSAGE=${1}
    echo -e  "${HILITE}${MESSAGE}${NORMAL}"
}

prompt() {
    local MESSAGE=${1}
    echo -en "${PROMPT}${MESSAGE}${NORMAL}"
}

enter() {
    local MESSAGE=${1}
    hilite "${MESSAGE}"
    prompt "Press Enter to continue..." && read
}

yorn() {
    local MESSAGE=${1}
    prompt "${MESSAGE} [y/N] " && read YORN && [[ "${YORN}" == [Yy]* ]]
}

sudo() {
    echo $@ | tee -a ${UPDATE_SCRIPT}
}

checkErrors() {
    hilite "Listing systemd failed units..."
    systemctl --failed

    hilite "\nListing systemd errors since current boot..."
    journalctl --no-pager -b -x -p 3

    hilite "\nListing X11 errors..."
    awk '/\(==\) Log file: / { s="" } /\((EE|WW)\)/ { s=s $0 RS } END { printf "%s", s }' ${XDG_DATA_HOME}/xorg/Xorg.0.log

    [ -s ${XDG_DATA_HOME}/xmonad/xmonad.errors ] && hilight "\nListing xmonad.errors..."
}

ctouch() {
    local SOURCE=${1}
    local TARGET=${2}
    chown -cRP $(id -un):$(id -gn) ${SOURCE} ${TARGET}
    find ${SOURCE} ${TARGET} -type d -exec chmod 700 {} +
    find ${SOURCE} ${TARGET} -type f ! -name \*.sh -exec chmod 600 {} +
    find ${SOURCE} ${TARGET} -type d -name bin -execdir chmod -cR 700 {} +
}

crsync() {
    local SOURCE=${1}
    local TARGET=${2}
    local OPTIONS="-a -v --delete"
    local RTEST="rsync --dry-run ${OPTIONS} ${RSYNC_EXCLUDES} ${SOURCE}/ ${TARGET}"
    local RSYNC="rsync           ${OPTIONS} ${RSYNC_EXCLUDES} ${SOURCE}/ ${TARGET}"
    ${RTEST} | tee ${DATA_PATH}/rtest.log
    if yorn "Continue?"; then
        ${RSYNC} | tee ${DATA_PATH}/rsync.log
    fi
}

backupSystem() {
    hilite "Backing installed packages..."
    pacman -Qent | tee ${PACKAGES_INSTALLED}

    hilite "\nBacking packages database..."
    tar cJf ${PACKAGES_DATABASE} /var/lib/pacman/local

    hilite "\nBacking configuration files..."
    installPackages etckeeper && etckeeper
    # pacman -Qii | awk '/^MODIFIED/ { print $2 }' | xargs -r cp --parents -t ${DATA_PATH}
    pacman -Qii | awk '/^MODIFIED/ { print $2 }' | xargs tar cJf ${PACKAGES_CONFIG}

    if yorn "Backup ${RSYNC_SOURCE} to ${RSYNC_TARGET}?"; then
        enter "Connect and mount backup disk..."
        ctouch ${RSYNC_SOURCE} ${RSYNC_TARGET}
        crsync ${RSYNC_SOURCE} ${RSYNC_TARGET}
    fi
    if yorn "Backup system and user data to encrypted disk?"; then
        enter "Connect and mount encrypted disk..."
        ctouch ${CRYPT_SOURCE} ${CRYPT_TARGET}
        crsync ${CRYPT_SOURCE} ${CRYPT_TARGET}
    fi
}

restoreSystem() {
    hilite "Restoring installed packages..."
    sudo pacman -S --needed $(awk '{ print $1 }' ${PACKAGES_INSTALLED})

    hilite "\nRestoring packages database..."
    sudo tar xJf ${PACKAGES_DATABASE} -C /

    hilite "\nRestoring configuration files..."
    # find ${DATA_PATH}/{etc,usr} -type f -exec sh -c 'echo "cp {} /$(realpath --relative-to=$0 $1)"' ${DATA_PATH} {} \;
    sudo tar xJf ${PACKAGES_CONFIG} -C /

    if yorn "Restore system and user data to disk?"; then
        enter "Connect and mount restore disk..."
        crsync ${RSYNC_TARGET} ${RSYNC_SOURCE}
    fi
    if yorn "Restore system and user data from encrypted disk?"; then
        enter "Connect and mount encrypted disk..."
        crsync ${CRYPT_TARGET} ${CRYPT_SOURCE}
    fi
}

RESET="\x1b\[0;0m"
A_HREF="\x1b\[4;34m"
A_NAME="\x1b\[1;34m"
CODE="\x1b\[0;32m"
EM="\x1b\[3;33m"
STRONG="\x1b\[1;33m"

xmlUnescape() {
    local XML=${1}
    echo ${XML} | \
        sed -e "s/&amp;/&/g" \
            -e "s/&lt;/</g" -e "s/&gt;/>/g" \
            -e "s/<a href=\"\([^\"]*\)\">/\[\[${A_HREF}\1${RESET}\]\[${A_NAME}/g" -e "s/<\/a>/${RESET}\]\]/g" \
            -e "s/<br \/>/\n/g" \
            -e "s/<code>/${CODE}/g" -e "s/<\/code>/${RESET}/g" \
            -e "s/<em>/${EM}/g" -e "s/<\/em>/${RESET}/g" \
            -e "s/<p>//g" -e "s/<\/p>/\n/g" \
            -e "s/<pre>//g" -e "s/<\/pre>//g" \
            -e "s/<strong>/${STRONG}/g" -e "s/<\/strong>/${RESET}/g"
}

fetchNews() {
    local IFS=">"
    hilite "Fetching news..."
    curl -s ${NEWS_FEED} | while read -d "<" TAG CDATA; do
        case ${TAG} in
            item)
                title=""
                link=""
                description=""
                pubDate=""
                guid=""
                ;;
            title)
                title=$(xmlUnescape ${CDATA})
                ;;
            link)
                link=${CDATA}
                ;;
            description)
                description=$(xmlUnescape ${CDATA})
                ;;
            pubDate)
                pubDate=$(date -d ${CDATA} -I"date")
                ;;
            guid*)
                guid=${CDATA}
                ;;
            /item)
                if ! grep $guid ${NEWS_FILE} &> /dev/null; then
                    cat <<EOF | tee -a ${NEWS_FILE}
Title:          $title
Link:           $link
Global UID:     $guid
Date:           $pubDate
Description:    $description

EOF
                fi
                ;;
        esac
    done
}

updateMirrors() {
    hilite "Listing mirrors..."
    awk '/^Server = / { print $3 }' /etc/pacman.d/mirrorlist

    hilite "\nUpdating mirrorlist..."
    curl -s ${MIRROR_LIST} | sed -e 's/^#Server/Server/' -e '/^#/d' | tee ${MIRROR_FILE}
    if installPackages pacman-contrib; then
        curl -s ${MIRROR_LIST} | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -n 5 - | tee ${MIRROR_FILE}
    fi
    sudo pacman -Syy
}

installPackages() {
    local PACKAGES=($@)
    pacman -Qs ${PACKAGES[*]} || (yorn "Install ${PACKAGES[*]}?" && sudo pacman -S ${PACKAGES[*]})
}

removePackages() {
    local PACKAGES=($@)
    if ! yorn "Remove all listed packages?"; then
        for PACKAGE in ${PACKAGES[@]}; do
            yorn "Remove ${PACKAGE}?" || PACKAGES=(${PACKAGES[@]/${PACKAGE}}) # TODO
        done
    fi
    [ ${#PACKAGES[@]} -gt 0 ] && sudo pacman -Rns ${PACKAGES[*]}
}

upgradePackages() {
    # fetchNews && updateMirrors

    hilite "Checking updates..."
    installPackages pacman-contrib && checkupdates

    hilite "\nUpgrading packages..."
    sudo pacman -Syu

    hilite "\nListing upgrade errors..."
    sudo awk \''/\[PACMAN\] Running \47pacman -Syu\47/ { s="" } /[Ww]arning/ { s=s $0 RS } END { printf "%s", s }'\' /var/log/pacman.log

    hilite "\nUpdating locate database..."
    sudo updatedb

    hilite "\nLocating .pac{new,save} files..."
    sudo locate --existing .pac{new,save}
    installPackages pacdiff && pacdiff

    # cleanFilesystem
}

cleanFilesystem() {
    hilite "Removing orphaned packages..."
    pacman -Qdnt | tee ${PACKAGES_ORPHANED}
    removePackages $(pacman -Qdntq | tr '\n' ' ')

    hilite "\nRemoving foreign packages..."
    pacman -Qem  | tee ${PACKAGES_FOREIGN}
    removePackages $(pacman -Qemq  | tr '\n' ' ')

    hilite "\nCleaning packages cache..."
    installPackages paccache && paccache -r
    sudo pacman -Sc
    yorn "Remove all cached packages?" && sudo pacman -Scc

    hilite "\nListing unowned files..."
    installPackages pacutils && pacreport --unowned-files
    installPackages lostfiles && lostfiles
    find /etc /opt /usr /var \
         -path /etc/ca-certificates -prune -o \
         -path /etc/ssl/certs -prune -o \
         -path /usr/share -prune -o \
         -path /var/cache/pacman/pkg -prune -o \
         -path /var/lib/pacman/local -prune -o \
         -print \
        | pacman -Qqo - 2>&1 > /dev/null | awk '{ print $5 }' > ${GHOST_FILES}

    hilite "\nListing broken symlinks..."
    find / -xtype l -print 2>/dev/null | tee ${BROKEN_LINKS}
}

scanMalware() {
    hilite "Updating ClamAV..."
    sudo freshclam
    sudo chmod 644 /var/lib/clamav/daily.cld
    hilite "\nScanning for viruses..."
    echo clamscan -r ${HOME}

    hilite "\nUpdating rkhunter..."
    sudo rkhunter --propupd
    hilite "\nScanning for rootkits..."
    sudo rkhunter -c -sk
    sudo grep Warning /var/log/rkhunter.log
    sudo rkhunter --enable deleted_files,hidden_procs,suspscan,hidden_ports,packet_cap_apps,apps -sk
    sudo grep Warning /var/log/rkhunter.log

    # hilite "Updating chkrootkit..."
    # sudo chkrootkit
}

main() {
    local OPTIONS=('checkErrors' 'backupSystem' 'fetchNews' 'updateMirrors' 'upgradePackages' 'cleanFilesystem' 'scanMalware')
    local OPTIONS_INTERACTIVE=(${OPTIONS[*]} 'restoreSystem')
    local INTERACTIVE=
    local YES=

    menu() {
        hilite "Enter option or press C-c to quit."
        select o; do
            if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $# ]; then $o; fi
        done
    }

    while getopts hiy opt; do
        case $opt in
            h) echo "./${BASE_NAME} [-hiy]" && exit 0 ;;
            i) INTERACTIVE=1 ;;
            y) YES=1 ;;
        esac
    done

    if [ -z "${INTERACTIVE}" ]; then
        for option in ${OPTIONS[@]}; do $option; done
    else
        menu ${OPTIONS_INTERACTIVE[@]}
    fi
}

main $@
