#!/bin/bash
#
# Install all required Git Hook Scripts
#
# Author : Jacques Raphanel
# Version: 1.2

progpath=$0
progdir=${progpath%/*}
prog=${progpath##*/}

# URL to the github project containing all required scripts
GITHUB_URI=https://raw.githubusercontent.com/sismicfr/git-hooks/main
# Path to local hooks directory
LOCAL_HOOKS_DIR=$(git rev-parse --show-toplevel 2> /dev/null)
# Global template directory
GLOBAL_TEMPLATE_DIR=$(git config --global --list | grep "init.templatedir" | cut -d= -f2)
# List of supported hook scripts
LIST_HOOK_SCRIPTS="pre-commit commit-msg doCommit.sh doCreateBranch.sh"

if [ -n "${LOCAL_HOOKS_DIR}" ]; then
    LOCAL_HOOKS_DIR="${LOCAL_HOOKS_DIR}/.git/hooks"
fi

# set argument default values
prefix=
local=n
globalonly=n
verbose=n

# apply SGR code to message
sgr() {
    local fd=$1
    local code=$2
    local msg=$3
    local out="\033[${code}m${msg}\033[0m"
    echo "$out"
}

# print message on stderr then exit
echo_error() {
    local firstln=1
    while [ $# -gt 0 ]; do
        if [ $firstln -eq 1 ]; then
            local msg
            msg="$(sgr 2 31 ERROR): $1"
            firstln=0
        elif [ "$1" = 'tryhelp' ]; then
            msg="${msg}\n  Try \`$progpath --help' for more information"
        else
            msg="${msg}\n  $1"
        fi
        shift
    done
    echo -e "${msg}" >&2
    exit 1
}

# print warning message on stdout
echo_warning() {
    echo -e "$(sgr 1 33 WARNING): $1"
}

# print warning message on stdout
echo_info() {
    echo -e "$(sgr 1 32 "$1")"
}

# print verbose message on stdout
echo_verbose() {
    if [ "$verbose" = "y" ]; then
        echo -e "$(sgr 1 94 "DEBUG  "): $1"
    fi
}

# print usage message
echo_usage() {
    [ -z "$prefix" ] && prefix=${GLOBAL_TEMPLATE_DIR} || true
    echo "Usage: $progpath [OPTION]...

Check requirements then set variables and install all required scripts.
Defaults for the options are specified in square brackets.

Configuration:
  -h, --help              display this help and exit
  -g, --global            make global installation only [false]
  -l, --local             prefer local .git directory rather global
                          template directory [false]
  -v, --verbose           be more verbose [false]

Installation directories:
  --prefix=PREFIX         install files in PREFIX [$prefix]
"
}

# Check if one version is less or equal than another version
# verlte VERSION1 VERSION2
verlte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ] && return 1 || return 0
}

# Check if one version is less than another version
# verlte VERSION1 VERSION2
verlt() {
    [ "$1" = "$2" ] && return 1 || verlte $1 $2
}

# Extract version number from local script given by its name
# extract_local_version PATH
extract_local_version() {
    if [ -f "$1" ]; then
        echo `grep -Eo '(Version: [0-9.]+)' $1 2>/dev/null | cut -d' ' -f2- 2>/dev/null`
    else
        echo ""
    fi
}

# Extract version number from remove script given by its name
# extract_remote_version PATH
extract_remote_version() {
    echo `curl -s -X GET ${GITHUB_URI}/$1 | grep -Eo '(Version: [0-9.]+)'  | cut -d' ' -f2- 2>/dev/null`
}

# Update local script given by a directory path and file name
# update_local_script DIR FILENAME
update_local_script() {
    local scriptExists=$(test -f "$1/$2" && echo 0 || echo 1)
    mkdir -p "$1"
    if curl -s -X GET ${GITHUB_URI}/$2 -o $1/$2; then
	chmod +x $1/$2
        if [ $scriptExists -eq 0 ]; then
            echo_info "$1/$2 upgraded from $3 to $4"
        else
            echo_info "$1/$2 installed [$4]"
        fi        
    else
        echo_error "failed to install $2 in $1"
    fi
}

echo_verbose "processing command-line arguments ..."

# parse arguments
for arg in "$@"; do
   # set argument value defined with "--arg val" form
    if [ -n "${nextargisval+x}" ]; then
        declare "$nextargisval"="$arg"
        unset nextargisval
        continue
    fi
    case $arg in
        --prefix=*)
            prefix="${arg#*=}"
            ;;
        --prefix)
            nextargisval=prefix
            ;;
        -g|--global)
            global=y
            ;;
        -l|--local)
            if [ -n "${LOCAL_HOOKS_DIR}" ]; then
                local=y
            else
                echo_warning "The script is executed outside of any git directory, so ignore $arg option"
            fi
            ;;
        -v|--verbose)
            verbose=y
            ;;
        -h|--help)
            echo_usage
            exit 0
            ;;
        -*)
            echo_error "Unrecognized option \`$arg'" "tryhelp"
            ;;
        *=*)
            echo -e "Export \`$arg' in environment" ;
            export "${arg?}"
            ;;
    esac
done

if [ -z "$GLOBAL_TEMPLATE_DIR" ]; then
    # No global template directory defined yet, so use default one
    echo_verbose "no global template directory defined yet, so update global git configuration"
    GLOBAL_TEMPLATE_DIR=$HOME/.git-templates
    git config --global init.templatedir "$GLOBAL_TEMPLATE_DIR"
    mkdir -p "$GLOBAL_TEMPLATE_DIR/hooks"
fi

if [ ! -d "$GLOBAL_TEMPLATE_DIR/hooks" ]; then
    mkdir -p "$GLOBAL_TEMPLATE_DIR/hooks"
fi

if [ -z "$prefix" ]; then
    # Determine automatically the targeted template directory
    if [ "$local" = "n" -o "$global" = "y" ]; then
        prefix=$HOME/.git-templates/hooks
    else
        prefix="$LOCAL_HOOKS_DIR"
    fi
fi

[ ! -d "$prefix" ] && mkdir -p "$prefix" || true

for file in $LIST_HOOK_SCRIPTS; do
    echo_verbose "extracting version number from local $file script ..."
    localVersion=$(extract_local_version "$LOCAL_HOOKS_DIR/$file")
    globalVersion=$(extract_local_version "$GLOBAL_TEMPLATE_DIR/hooks/$file")
    remoteVersion=$(extract_remote_version "$file")

    if [ -z "$remoteVersion" ]; then
        echo_warning "skip $file script since not available from remote repository"
        continue
    fi

    if [ -n "${LOCAL_HOOKS_DIR}" -a "$global" = "n" ]; then
        if [ -n "$localVersion" ]; then
            # Check local script
            if verlt $localVersion $remoteVersion; then
                update_local_script "$LOCAL_HOOKS_DIR" "$file" "$localVersion" "$remoteVersion"
            else
                echo_verbose "$GLOBAL_TEMPLATE_DIR/hooks/$file is already up-to-date ($localVersion)"
            fi
        else
            update_local_script "$LOCAL_HOOKS_DIR" "$file" "$localVersion" "$remoteVersion"
        fi
    fi

    if [ -n "$globalVersion" ]; then
        # Check global script
        if verlt $globalVersion $remoteVersion; then
            update_local_script "$GLOBAL_TEMPLATE_DIR/hooks" "$file" "$globalVersion" "$remoteVersion"
        else
            echo_verbose "$GLOBAL_TEMPLATE_DIR/hooks/$file is already up-to-date ($globalVersion)"
        fi
    else
        update_local_script "$GLOBAL_TEMPLATE_DIR/hooks" "$file" "$globalVersion" "$remoteVersion"
    fi
done
