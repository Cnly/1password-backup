#!/bin/bash
set -e
####################################################################
# 1Password Cloud Backup                                           #
# backup                                                           #
#                                                                  #
# https://github.com/michael-batz/1password-backup                 #
####################################################################

print_usage()
{
    echo "1Password Cloud Backup"
    echo "usage: $0 -k <public key identifier> [-e <path to op>] [-f <output file>]"
    exit 0
}

# define variables
tool_op="op"
tool_jq="jq"

# parse arguments
while getopts "f:k:e:" option
do
    case "${option}" in
        f) var_outputfile=${OPTARG};;
        k) var_pubkey=${OPTARG};;
        e) tool_op=${OPTARG};;
        *) print_usage
    esac
done

echo "1Password Cloud Backup"

# check arguments
if [ -z "${var_pubkey}" ]; then print_usage; fi
if [ ! -x "${tool_op}" -a -z "$(command -v ${tool_op} 2> /dev/null)" ]; then
    echo "- ${tool_op} is not executable"
    exit 1
fi
if [ ! -x "${tool_jq}" -a -z "$(command -v ${tool_jq} 2> /dev/null)" ]; then
    echo "- ${tool_jq} is not executable"
    exit 1
fi
if ! command -v timeout 2> /dev/null; then
    echo "timeout is not executable"
    exit 1
fi

echo "- Checking the public key to use..."
echo ""

gpg --list-keys ${var_pubkey}

# signin to 1Password
echo "- Signing in to 1Password..."
eval $(${tool_op} signin)

# get a list of all items
echo "- Geting list of all items from 1Password..."
items_json=$(${tool_op} list items)
items=$(echo ${items_json} | ${tool_jq} --raw-output '.[].uuid')

nitems=$(echo ${items_json} | ${tool_jq} '. | length')
echo "- ${nitems} items in total"

if [ -z "${var_outputfile}" ]; then
    var_outputfile="1Password Backup - $(date +'%Y-%m-%d %H-%M-%S') - ${nitems} Items.gpg"
    echo "- Output file unspecified. Will use: ${var_outputfile}"
fi

# get all items from 1Password
output=""
curr=0
for item in $items
do
    ((curr+=1))
    echo "  - Getting item ${item} (${curr}/${nitems})"

    retries=10
    has_retried=
    while ((retries > 0)); do
        item_obj=$(timeout -k 15 10 ${tool_op} get item ${item}) && break

        echo "    - op exited with code $?. Waiting for 3 seconds before retrying..."
        sleep 3
        has_retried=1
        ((retries --))
    done
    if ((retries == 0 )); then
        echo "Unable to get item ${item} after ${retries} retries! Aborting."
        exit 1
    fi

    if [ ! -z "${has_retried}" ]; then
        echo "    - Got item ${item} through retrying"
    fi

    output+=${item_obj}

done

# encrypt items and write to output file
echo "- Storing items in encrypted output file ${var_outputfile}..."
echo $output | \
    jq -n '[inputs]' | \
    gpg --armor \
    --output "${var_outputfile}" \
    --recipient "${var_pubkey}" \
    --encrypt -

# signout from 1Password
echo "- Signing out from 1Password"
${tool_op} signout
