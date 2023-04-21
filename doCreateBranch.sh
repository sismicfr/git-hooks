#!/bin/bash

# Dedicated script to facilitate the branch creation.
#
# The script will guide the end-user step by step to collect all required
# information to create a new branch.
#
# Author : Jacques Raphanel
# Version: 1.0
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

    tput civis
    tput sc
    print_menu "$selected_item" "${menu_items[@]}"
    
    while read -rsn1 input
    do
        case "$input" in
            $'\x1B')  # ESC ASCII code (https://dirask.com/posts/ASCII-Table-pJ3Y0j)
                read -rsn1 -t 0.1 input
                if [ "$input" = "[" ]; then
                    # occurs before arrow code
                    read -rsn1 -t 0.1 input
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
                read -rsn5 -t 0.1  # flushing stdin
                ;;
            "")  # Enter key
                tput cnorm
                return "$selected_item"
                ;;
        esac
    done
}

check_git_repository() {
    if ! git status >& /dev/null; then
        echo_err "$PWD is not a git repository"
        exit 1
    fi
    if [ -z "${source_branch}" ]; then
        echo_err "failed to get the current branch name"
        exit 1
    fi
}

# We need to be in a git repository
source_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
check_git_repository

echo ""
echo ""

# Select the commit type
selected_item=0
menu_items=('feat:         A new feature' ) 
menu_items+=('bugfix:       A bug fix detected during development cycle' )
menu_items+=('hotfix:       A bug fix detected as part of released version' )
menu_items+=('experimental: Test or experiment a new feature or idea' )
menu_items+=('build:        Changes to to the build process')

echo_info "? Select the type of change that you're commiting: (Use arrow keys)"
run_menu "$selected_item" "${menu_items[@]}"
menu_result="$?"
btype=$(echo ${menu_items[$menu_result]} | cut -d: -f1)

# Enter short description/subject without space
subject=""
while [ -z "${subject// /}" ]; do
    echo ""
    echo_info "? A description MUST immediately follow the branch name prefix. The description is a short description of the changes."
    read -p "Enter a branch description: " subject
done
# ensure that no space character present
subject=${subject// /-}

# Enter Jira user-story reference
jiraus=""
while true; do
    echo ""
    echo_info "? The associated JIRA user-story reference. Optional in case of experimental branch type"
    read -p "Enter the jira reference: " jiraus
    if [[ "$jiraus" =~  ^[A-Z]{2,6}-[0-9]{1,6}$ ]]; then
        # Properly formatted
        break
    elif [ -z "${jiraus}" -a "${btype}" = "experimental" ]; then
        # Optional in case of experimental branch
        break
    elif [ "${jiraus}" = "no-ref" -a "${btype}" = "experimental" ]; then
        # no-ref is only allowed in case of experimental branch
        break
    fi
done

# Enter the source branch name
while true; do
    echo ""
    echo_info "? The source branch name from which you want to create your new branch"
    read -p "Enter the branch name [${source_branch}]: " branch
    if [ -z "${branch}" ]; then
        branch=${source_branch}
    fi

    # Ensure that the branch name really exists
    if git branch -a | grep -qc "${branch}\$"; then
        break
    fi
    echo_err "${branch} : branch not found, please verify its existence or enter a new name"
done

new_branch="${btype}/${subject}"
if [ -n "${jiraus}" ]; then
    new_branch+="/${jiraus}"
fi
while true; do
    read -p "Do you really want to create ${new_branch} from ${branch}? [Y/n] " confirm
    if [ "${confirm,,}" = "n" ]; then
        # Skip branch creation
        exit 0
    fi
    if [ -z "${confirm:-}" -o "${confirm,,}" = "y" ]; then
        # Accept branch creation
        break
    fi
done

echo ""
echo_info "creating ${new_branch} ..."
git checkout -b "${new_branch}" "${branch}"
echo ""