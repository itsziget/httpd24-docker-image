#!/usr/bin/env bash

toBool () {
    local BOOL=$(echo "${1}" | tr '[:upper:]' '[:lower:]');
    case ${BOOL} in
        1|yes|on|true) echo "true"; ;;
        0|no|off|false) echo "false"; ;;
        *) echo "null";
    esac;
}

getConfigPath () {
    local CONF_NAME="${1}";
    local ABSOLUTE="${2}";
    local ABSOLUTE_BOOL="$(toBool "${ABSOLUTE}")";
    local CONF_DIR="conf/extra";

    if [ -z "${CONF_NAME}" ]; then
        CONF_NAME="httpd";
        CONF_DIR="conf";
    elif [ "${CONF_NAME:0:1}" == "@" ]; then
        CONF_NAME="${CONF_NAME:1}";
        CONF_DIR="conf/custom-extra"
    fi;

    if [ "${ABSOLUTE_BOOL}" == "true" ]; then
        CONF_DIR="/usr/local/apache2/${CONF_DIR}";
    fi;

    echo ${CONF_DIR}/${CONF_NAME}.conf
};

switchModule () {
    local MODULE_NAME="${1}";
    local MODULE_STATUS="${2}";
    local MODULE_STATUS_BOOL=$(toBool "${MODULE_STATUS}");
        
    local LOAD_MODULE_PATTERN='LoadModule\s\+'${MODULE_NAME}'_module\s\+modules/mod_'${MODULE_NAME}'.so';
    
    case ${MODULE_STATUS_BOOL} in
        true)  sed -i 's~^\s*#\(\s*'"${LOAD_MODULE_PATTERN}"'\)~\1~g' ${CONF}; ;;
        false) sed -i 's~^\s*\(\s*'"${LOAD_MODULE_PATTERN}"'\)~#\1~g' ${CONF}; ;;
    esac;
};

switchConfig () {
    local CONF_NAME="${1}";
    local CONF_STATUS="${2}";
    local CONF_STATUS_BOOL=$(toBool "${CONF_STATUS}");
    
    local INCLUDE_CONF_PATTERN="Include\s\+$(getConfigPath ${CONF_NAME})";
    
    case ${CONF_STATUS_BOOL} in
        true)  sed -i 's~^\s*#\(\s*'"${INCLUDE_CONF_PATTERN}"'\)~\1~g' ${CONF}; ;;
        false) sed -i 's~^\s*\(\s*'"${INCLUDE_CONF_PATTERN}"'\)~#\1~g' ${CONF}; ;;
    esac;
};

switchModules () {
    local MODULE_NAMES="${1}";
    local MODULE_STATUS="${2}";
    
    ORIG_IFS="${IFS}";
    IFS=$'\t\n\r, ';
    for MODULE_NAME in ${MODULE_NAMES}; do
        switchModule "${MODULE_NAME}" "${MODULE_STATUS}";
    done;    
    IFS="${ORIG_IFS}"
};

switchConfigs () {
    local CONF_NAMES="${1}";
    local CONF_STATUS="${2}";
    
    ORIG_IFS="${IFS}";
    IFS=$'\t\n\r, ';
    for CONF_NAME in ${CONF_NAMES}; do
        switchConfig "${CONF_NAME}" "${CONF_STATUS}";
    done;    
    IFS="${ORIG_IFS}"
};

getLineNumbersOf () {
    local STR="${1}";
    local FILE_PATH="${2}";
    
    if [ -z "${FILE_PATH}" ]; then
        grep -n "${STR}" | cut -d ':' -f1;
    else
        grep -n "${STR}" "${FILE_PATH}" | cut -d ':' -f1;
    fi;
};

getLineNumberOf () {
    getLineNumbersOf "${1}" "${2}" | head -n1
};

getDocRootDirLineNumbers () {
    local DOC_ROOT="$(getDocRoot)";
    local LINE_START=$(getLineNumberOf '^<Directory "'"${DOC_ROOT}"'">' "${CONF}");
    local DIR_BLOCK_HEIGHT=$(tail -n +${LINE_START} "${CONF}" | getLineNumberOf '^</Directory>');
    local LINE_END=$((LINE_START + DIR_BLOCK_HEIGHT - 1));
    echo "${LINE_START},${LINE_END}";
}

getDocRoot () {
    local DOC_ROOT="/usr/local/apache2/htdocs";
    local SAVED_DOC_ROOT="";
    if [ -f "${HOME}/httpd-docroot" ]; then
        SAVED_DOC_ROOT="$(cat "${HOME}/httpd-docroot")";
        if [ -n "${SAVED_DOC_ROOT}" ]; then
            DOC_ROOT="${SAVED_DOC_ROOT}";
        fi;
    fi;
    echo "${DOC_ROOT}"
};

setDocRoot () {
    local NEW_DOCROOT="${1}";
    local OLD_DOCROOT="$(getDocRoot)";
    if [ -z "${SRV_DOCROOT}" ]; then
        sed -i 's#DocumentRoot .*#DocumentRoot '"${OLD_DOCROOT}"'#g' ${CONF}
        sed -i 's#<Directory\s\+"'"${OLD_DOCROOT}"'">#<Directory "/usr/local/apache2/htdocs">#g' ${CONF}
    else
        sed -i 's#DocumentRoot .*#DocumentRoot '${NEW_DOCROOT}'#g' ${CONF}
        sed -i 's#<Directory\s\+"'"${OLD_DOCROOT}"'">#<Directory "'${NEW_DOCROOT}'">#g' ${CONF}
    fi
    
    echo "${NEW_DOCROOT}" > "${HOME}/httpd-docroot";
};

allowOverride () {
    local AO_STATUS="${1}";
    local AO_STATUS_BOOL="$(toBool "${AO_STATUS}")";
    local LN="$(getDocRootDirLineNumbers)";
    
    local AO_VALUE="";
    case "${AO_STATUS_BOOL}" in
        true) AO_VALUE="All"; ;;
        false) AO_VALUE="None"; ;;
        *) AO_VALUE="${AO_STATUS}"; ;;
    esac;
    
    sed -i "${LN}"'s#^\(\s*\)AllowOverride\s\+.*#\1AllowOverride '"${AO_VALUE}"'#g' "${CONF}";
};

generateSSL () {
    local SSL_CERT="${1}";
    local SSL_KEY="${2}";
    
    local OPENSSL_INSTALLED=$(dpkg -l openssl 2>/dev/null | wc -l)
    if [ "${OPENSSL_INSTALLED}" == "0" ]; then
        apt-get update && apt-get install -y --no-install-recommends openssl
    fi;
    
    openssl req -new -x509 -days 365 -nodes -out "${SSL_CERT}" -keyout "${SSL_KEY}" -batch
};

setAdminEmail (){
    local EMAIL="${1}";
    
    if [ -z "${EMAIL}" ]; then
        EMAIL="you@example.com";
    fi;
    
    sed -i 's/^\s*ServerAdmin .*/ServerAdmin '${EMAIL}'/g' ${CONF}
};

setServerName () {
    local SERVER_NAME="${1}";
    
    if [ -z "${SERVER_NAME}" ]; then
        SERVER_NAME="localhost.localdomain";
    fi;
   
    sed -i 's/^\s*ServerName .*/ServerName '${SERVER_NAME}'/g' ${CONF}
};

selectCertName () {
    if [ -n "${SRV_SSL_NAME}" ]; then
        echo ${SRV_SSL_NAME};
    elif [ -n "${CERT_NAME}" ]; then
        echo "${CERT_NAME}";
    elif [ -n "${SRV_NAME}" ]; then
        echo "${SRV_NAME}";
    elif [ -n "${VIRTUAL_HOST}" ] && [ -n "${VIRTUAL_HOST##*,*}" ]; then
        echo "${VIRTUAL_HOST}";
    else
        echo "ssl";
    fi;
};

CONF=$(getConfigPath "" "true");
PCONF=$(getConfigPath "@php" "true");
SCONF=$(getConfigPath "@ssl" "true");
RPCONF=$(getConfigPath "@reverse-proxy" "true");