#!/usr/bin/env bash

set -e

PROJECT_ROOT="${0%/*}/..";
cd "${PROJECT_ROOT}"

GIT_HASH=""

source "${PROJECT_ROOT}/ci/resources.sh"

CI_DRY_RUN="";
CI_BRANCH="";
CI_TAG=""
CI_IMAGE_NAME=""
CI_SKIP_TEST=""
CI_DOCKER_START_TIMEOUT="180"
CI_EVENT_TYPE=""
CI_REPOSITORY_ALIAS="origin"
CI_BUILD_NUMBER="${GIT_HASH}"

while getopts ":t:b:i:T:e:B:dhs" opt; do
    case ${opt} in
        d) CI_DRY_RUN="y"; ;;
        t) CI_TAG="${OPTARG}"; ;;
        T) CI_DOCKER_START_TIMEOUT="${OPTARG}"; ;;
        b) CI_BRANCH="${OPTARG}"; ;;
        i) CI_IMAGE_NAME="${OPTARG}"; ;;
        s) CI_SKIP_TEST="y"; ;;
        r) CI_REPOSITORY_ALIAS="${OPTARG}"; ;;
        B) CI_BUILD_NUMBER="${OPTARG}"; ;;
        e)
            case "${OPTARG}" in
                push|api|cron) CI_EVENT_TYPE="${OPTARG}"; ;;
                *) >&2 echo "Invalid event type: ${OPTARG}"; exit 1; ;;
            esac;
            ;;
        h)
            echo "Usage: $0 [-d] [-t <string>] [-b <string>] [-i <string>] [-e <string>] [-r <string>] [-d] [-s] [-h]";
            echo "Options:"
            echo -e "\t-d\t\tJust print commands without running them";
            echo -e "\t-t <string>\tGit commit tag if the build was triggered by tag. Do not use it anyway!";
            echo -e "\t-b <string>\tGit branch if the build was triggered by branch. If \"-t\" was given too, \"-b\" will always be ignored!";
            echo -e "\t-i <string>\tDocker image name without version tag.";
            echo -e "\t-s\t\tSkip running tests";
            echo -e "\t-e <string>\tEvent type. Valid types: ";
            echo -e "\t-r <string>\tRemote repository alias. Default: origin"
            echo -e "\t-B <string>\tBuild number. git commit hash by default"
            echo -e "\t-h\t\tShows this help message";
            exit 0;
            ;;
        *)
            >&2 echo "Invalid option: -${OPTARG}. Use \"-h\" to get help."
            exit 1;
            ;;
    esac;
done;
shift $((OPTIND-1))

[ -n "${CI_TAG}" ] && CI_BRANCH="${CI_TAG}"; # for easier local test

reqVarNonEmpty CI_IMAGE_NAME
reqVarNonEmpty CI_BRANCH
reqVarNonEmpty GIT_HASH
reqVarNonEmpty CI_EVENT_TYPE

if [ "${CI_EVENT_TYPE}" == "cron" ]; then
    if [ "$(isBranch)" ]; then
        if [ "$(isMinorBranch)" == "true" ]; then
            LATEST_VERSION="$(getLatestStableOrPreVersion "${CI_BRANCH}")";
            if [ -n "${LATEST_VERSION}" ]; then
                VERSION_CACHE="${LATEST_VERSION}";
                COMMAND='docker pull "'${CI_IMAGE_NAME}:${VERSION_CACHE}'"'
                echo ${COMMAND}
                [ "${CI_DRY_RUN}" != "y" ] && eval "${COMMAND}"

                git clone --branch "v${LATEST_VERSION}" $(git remote get-url "${CI_REPOSITORY_ALIAS}") ${PROJECT_ROOT}/.build
                cd ${PROJECT_ROOT}/.build
                # update git commit hash
                GIT_HASH="$(git rev-list -n 1 HEAD)"
                if [ "$(isImageDownloaded "${CI_IMAGE_NAME}:${GIT_HASH}")" ] && [ "$(isParentImageUpgraded "${CI_IMAGE_NAME}:${GIT_HASH}" "httpd:2.4")" == "true" ]; then
                    COMMAND='docker build --pull --cache-from "'${CI_IMAGE_NAME}:${VERSION_CACHE}'" --tag "'${CI_IMAGE_NAME}:${GIT_HASH}'" --tag "'${CI_IMAGE_NAME}:${GIT_HASH}' --tag "'${CI_IMAGE_NAME}:build-${CI_BUILD_NUMBER}'" .'

                    echo ${COMMAND}
                    [ "${CI_DRY_RUN}" != "y" ] && eval "${COMMAND}"

                    if [ "${CI_SKIP_TEST}" != "y" -a -f "${PROJECT_ROOT}/.build/test/__init__.py" ]; then
                        TEST_COMMAND='HTTPD_IMAGE_NAME="'${CI_IMAGE_NAME}'" HTTPD_IMAGE_TAG="'${GIT_HASH}'" HTTPD_WAIT_TIMEOUT="'${CI_DOCKER_START_TIMEOUT}'" py.test';
                        echo ${TEST_COMMAND}
                        [ "${CI_DRY_RUN}" != "y" ] && eval "${TEST_COMMAND}";
                    fi;
                fi;
            fi;
        fi;
    fi;
else
    VERSION_CACHE=$([ "$(isBranch)" == "true" ] && echo "${CI_BRANCH}-dev" || echo "${GIT_HASH}")


    COMMAND='docker pull "'${CI_IMAGE_NAME}:${VERSION_CACHE}'" || true'
    echo ${COMMAND}
    [ "${CI_DRY_RUN}" != "y" ] && eval "${COMMAND}"

    if [ "$(isBranch)" ]; then
        COMMAND='docker build --pull --cache-from "'${CI_IMAGE_NAME}:${VERSION_CACHE}'" --tag "'${CI_IMAGE_NAME}:${GIT_HASH}'" .'
        echo ${COMMAND}
        [ "${CI_DRY_RUN}" != "y" ] && eval "${COMMAND}"
        if [ "${CI_SKIP_TEST}" != "y" ]; then
            TEST_COMMAND='HTTPD_IMAGE_NAME="'${CI_IMAGE_NAME}'" HTTPD_IMAGE_TAG="'${GIT_HASH}'" HTTPD_WAIT_TIMEOUT="'${CI_DOCKER_START_TIMEOUT}'" py.test';
            echo ${TEST_COMMAND}
            [ "${CI_DRY_RUN}" != "y" ] && eval "${TEST_COMMAND}";
        fi;
    fi;
fi;

