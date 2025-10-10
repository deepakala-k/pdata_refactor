#!/bin/sh
# IBM_PROLOG_BEGIN_TAG
# This is an automatically generated prolog.
#
# $Source: src/usr/targeting/common/xmltohb/mergexml.sh $
#
# OpenPOWER HostBoot Project
#
# COPYRIGHT International Business Machines Corp. 2011,2014
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#
# IBM_PROLOG_END_TAG

#!/bin/bash
# Usage: ./merge_attributes.sh file1.xml file2.xml ... > merged.xml

# Exit if no files provided
if [ $# -eq 0 ]; then
    echo "Error: No input files given" >&2
    exit 1
fi

echo "<attributes>"

for file in "$@"; do
    # Check if file exists and is not empty
    if [ ! -s "$file" ]; then
        echo "Error: File '$file' not found or empty" >&2
        exit 1
    fi

    # Remove XML declaration, <attributes>, and </attributes> tags
    grep -v '<?xml' "$file" | \
    grep -v '<attributes>' | \
    grep -v '</attributes>'
done

echo "</attributes>"
