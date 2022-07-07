#!/usr/bin/env bash

set -e -o noglob

command=$1
paths=$2
workspace_dir=${GITHUB_WORKSPACE}
workspacer_parent_dir=$(dirname "$workspace_dir")

function ray_command_from_string() {
    case $1 in
        build)
        ray_command="build -e dist"
        ;;

        publish)
        ray_command="publish -f"
        ;;

        *)
        echo "Unsupported command. 'build' | 'publish'"
        return 1
        ;;
    esac
}

starting_dir=$PWD
ray_command_from_string $command
declare -a 'directories=('"$paths"')'

wildcard='/**'

declare -a directories_to_search=()

for dir in "${directories[@]}" ; do
    if ! [[ "$dir" =~ extensions/* ]] ; then
        continue
    fi
    absolute_dir="$workspace_dir/$dir"
    # create array with all directories to search
    # for normal case iterate upwards with all directories (try to not go above $workspace_dir) and then execute find on those
    # for ** case list all directories containing package.json with raycast && commands straight away

    if [[ "${absolute_dir}" == *"$wildcard" ]] ; then
        # if directory ends with wild card, find all subdirectories containing package.json, ignore node_modules folder
        absolute_dir=${absolute_dir%"$wildcard"}
        
        while IFS=  read -r -d $'\0'; do
            for reply in ${REPLY[@]}; do
                directory=$(dirname $reply)
                if [[ ! " ${directories_to_search[@]} " =~ " ${directory} " ]]; then
                    directories_to_search+=("${directory}")
                fi
            done
        done < <(find "$absolute_dir" -type d -name node_modules -prune -o -type f -name package.json -print0)
    else
        # for standard use case, search all parent directories as changed files may be deeper than folder containing package.json
        while [ "$absolute_dir" != $workspacer_parent_dir ];
        do
            if [ -d "$absolute_dir" ]; then
                if [[ ! " ${directories_to_search[@]} " =~ " ${absolute_dir} " ]]; then
                    directories_to_search+=("$absolute_dir")
                fi
            fi
            absolute_dir=$(dirname "$absolute_dir")
        done
    fi
done

declare -a extension_changed=()

for dir in "${directories_to_search[@]}"; do
    if [ -d "$dir" ]; then
        # make sure package.json contains commands and raycast
        if [[ $(find "$dir" -maxdepth 1 -type f -name 'package.json' -exec grep -iq "commands" {} \; -exec grep -il "raycast" {} \;) ]]; then
            if [[ ! " ${extension_changed[@]} " =~ " ${dir} " ]]; then
                extension_changed+=("$dir")
            fi
        fi
    fi
done

printf "🤖 %d Extensions found\n" "${#extension_changed[@]}"
printf '%s\n' "${extension_changed[@]}"

for dir in "${extension_changed[@]}" ; do
    printf "\nEntering $dir\n"
    cd "$dir"
    npm install
    printf "Executing 'ray $ray_command'\n"
    ray $ray_command --exitOnError
    cd $starting_dir
done
