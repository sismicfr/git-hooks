#!/bin/bash

# Dedicated script to facilitate the creation of new commit message
# following conventional commits specs.
#
# The script will guide the end-user step by step to collect all required
# information to generate appropriate commit message
#
# Author : Jacques Raphanel
# Version: 1.1
#

COLOR_RESET='\033[0m'
COLOR_ERROR='\033[31m'
COLOR_SELECTED='\e[32m'
COLOR_INFO='\033[94m'

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

ctrl_c() {
    tput cnorm
    exit 1
}

# Print an error message through stderr
echo_err() {
    printf "${COLOR_ERROR}ERROR: %s${COLOR_RESET}\n" "$@" >&2
}

# Print a normal text
echo_msg() {
    printf "%s\n" "$@"
}

# Print a selected text
echo_selected() {
    printf "${COLOR_SELECTED}%s${COLOR_RESET}\n" "$@"
}

# Print an informative text
echo_info() {
    printf "${COLOR_INFO}%s${COLOR_RESET}\n" "$@"
}

# selected_item, ...menu_items
print_menu() {
    local function_arguments=($@)

    local selected_item="$1"
    local menu_items=(${function_arguments[@]:1})
    local menu_size="${#menu_items[@]}"

    #for item in `echo "${menu_items[@]}"`; do
    for (( i = 0; i < $menu_size; ++i )); do
        if [ "$i" = "$selected_item" ]; then
            echo_selected "-> ${menu_items[$i]}"
        else
            echo_msg "   ${menu_items[$i]}"
        fi
    done
}

# selected_item, ...menu_items
function run_menu() {
    IFS=""
    local function_arguments=("$@")
    local selected_item="$1"
    local menu_items=(${function_arguments[@]:1})
    local menu_size="${#menu_items[@]}"
    local menu_limit=$((menu_size - 1))
    local timeout=0.1

    if [ "$(uname -s)" = "Darwin" ]; then
        timeout=1
    fi

    tput civis
    tput sc
    print_menu "$selected_item" "${menu_items[@]}"
    
    while read -rsn1 input
    do
        case "$input"
        in
            $'\x1B')  # ESC ASCII code (https://dirask.com/posts/ASCII-Table-pJ3Y0j)
                read -rsn1 -t $timeout input
                if [ "$input" = "[" ]; then
                    # occurs before arrow code
                    read -rsn1 -t $timeout input
                    case "$input" in
                        A)  # Up Arrow
                            if [ "$selected_item" -ge 1 ]; then
                                selected_item=$((selected_item - 1))
                                tput rc
                                tput sc
                                print_menu "$selected_item" "${menu_items[@]}"
                            fi
                            ;;
                        B)  # Down Arrow
                            if [ "$selected_item" -lt "$menu_limit" ]; then
                                selected_item=$((selected_item + 1))
                                tput rc
                                tput sc
                                print_menu "$selected_item" "${menu_items[@]}"
                            fi
                            ;;
                    esac
                fi
                read -rsn5 -t $timeout  # flushing stdin
                ;;
            "")  # Enter key
                tput cnorm
                return "$selected_item"
                ;;
        esac
    done
}

check_stagged_files() {
    IFSOLD=$IFS
    IFS=$'\n'
    local fileslist=($(git diff --cached --name-only 2>/dev/null))
    if [ -z "${fileslist}" ]; then
        echo_err "no file stagged yet"
        exit 1
    fi
    echo_info "Please find below the list of stagged files:"
    for file in  "${fileslist[@]}"; do
        echo "  $file"
    done
    IFS=$IFSOLD
}

# Ensure that at least one file is stagged
check_stagged_files

echo ""
echo ""

# Select the commit type
selected_item=0
menu_items=('feat:     A new feature' ) 
menu_items+=('fix:      A bug fix' )
menu_items+=('doc:      Documentation only changes' )
menu_items+=('style:    Changes that do not affect the meaning of the code (white-space, formatting, ...)')
menu_items+=('refactor: A code change that neither fixes a bug or adds a feature')
menu_items+=('perf:     A code change that improves performance')
menu_items+=('test:     Add missing tests')
menu_items+=('build:    Changes to to the build process')
menu_items+=('chore:    Changes that are not related to a fix or feature and do not modify the source or test files')

echo_info "? Select the type of change that you're commiting: (Use arrow keys)"
run_menu "$selected_item" "${menu_items[@]}"
menu_result="$?"
ctype=$(echo ${menu_items[$menu_result]} | cut -d: -f1)

# Enter the commit's scope
echo ""
echo_info "? An optional scope MAY be provided after a type. A scope is a phrase describing a section of the codebase."
read -p "Enter a custom commit's scope: " scope

# Enter short description/subject
subject=""
while [ -z "${subject// /}" ]; do
    echo ""
    echo_info "? A description MUST immediately follow the type/scope prefix. The description is a short description of the changes."
    read -p "Enter a custom commit's description: " subject
done

# Enter long description/body
echo ""
echo_info "? A longer commit body MAY be provided after the short description."

body=""
while true; do
    [ -z "$body" ] && read -p "Enter a commit's body: " line || read line
    [ -z "$line" ] && break || true
    [ -n "$body" ] && body+=$'\n' || true
    body+="$line"
done

msg="${ctype}"
if [ -n "${scope}" ]; then
    msg+="(${scope})"
fi
msg+=": $subject"
if [ -n "${body}" ]; then
    msg+=$'\n\n'
    msg+="${body}"
fi

git commit -m "$msg" "$@"
