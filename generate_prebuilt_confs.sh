#!/bin/bash
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear
#
# Script to create <target>_prebuilts.conf file by parsing manifest
#

get_target_products() {
    local targets_list=''
    targets=$(xmlstarlet sel -T -t -m \
        "//project/x-quic-distributable" \
        -v "@target-products" -o " " "$MANIFEST" \
       | tr ' ' '\n' | uniq)

    for tp in $targets; do
       targets_list="$( echo "$tp" | sed -e 's:,: :g' ) $targets_list"
    done

    target_products="$(echo "$targets_list" | xargs -n1 | sort -u | xargs)"
}

get_target_varaints() {
    local varaints_list=''
    varaints=$(xmlstarlet sel -T -t -m \
        "//project/x-quic-distributable" \
        -v "@package" -o " " "$MANIFEST" \
       | tr ' ' '\n' | uniq)

    for tv in $varaints; do
        varaints_list="$( echo "$tv" | sed -e 's:,: :g' ) $varaints_list"
    done

    target_varaints="$(echo "$varaints_list" | xargs -n1 | sort -u | xargs)"
    # ignore odr and grease variants
    target_varaints="$( echo "$target_varaints" | sed -e 's:odr::g' )"
    target_varaints="$( echo "$target_varaints" | sed -e 's:grease::g' )"
}

get_component_tag_for_pkg() {
    local pkg="prebuilt/{target_product}/$1"
    local quicdist="$(echo $(xmlstarlet sel -T -t -m "//project/x-quic-distributable" \
             -v "@path" -n -o " " "$MANIFEST" | grep "$pkg" | head -n 1))"

    local comptag="$(echo $(xmlstarlet sel -T -t -m "//project/x-quic-distributable [\
               contains(@path, '$quicdist')]" -v "../@x-component-tag" -n -o " " \
               "$MANIFEST" | head -n 1))"
    # If not available set build date as component tag
    comptag="${comptag:-$PBT_BUILD_DATE}"

    echo "${comptag/"refs/tags/"/}"
}

get_project_name_for_pkg() {
    local pkg="prebuilt/{target_product}/$1"
    local quicdist="$(echo $(xmlstarlet sel -T -t -m "//project/x-quic-distributable" \
             -v "@path" -n -o " " "$MANIFEST" | grep "$pkg" | head -n 1))"

    local project_name="$(echo $(xmlstarlet sel -T -t -m "//project[x-quic-distributable[contains(@path, '$quicdist')]]" \
               -v "@name" -n -o " " "$MANIFEST" | head -n 1))"

    echo "$project_name"
}

get_project_upstream_for_pkg() {
    local pkg="prebuilt/{target_product}/$1"
    local quicdist="$(echo $(xmlstarlet sel -T -t -m "//project/x-quic-distributable" \
             -v "@path" -n -o " " "$MANIFEST" | grep "$pkg" | head -n 1))"

    local project_upstream="$(echo $(xmlstarlet sel -T -t -m "//project[x-quic-distributable[contains(@path, '$quicdist')]]" \
               -v "@upstream" -n -o " " "$MANIFEST" | head -n 1))"

    echo "${project_upstream/"refs/tags/"/}"
}

# NOTE: hyphen (-) is not a valid identier in bash. Convert it to underscore(_)
create_prebuilt_conf() {
    local target="$1"; shift
    local pbconf="##AUTO GENERATED FILE. DON'T HAND EDIT."
    # Form a string of supported variants to pass on to xmlstarlet.
    for variant in $target_varaints; do
        local prebuilts=" $(xmlstarlet sel -T -t -m "//project/x-quic-distributable [\
                       contains(@target-products,'$target') and \
                       contains(@package,'$variant')]" \
                       -v "@path" -o " " "$MANIFEST" || true)"

        # Get list of pkgs to be included in this variant.
        local pkglist="$(echo $variant |tr '-' '_'|tr '.' '_DOT_')" ## Convert - to _
        declare -a ${pkglist}='( )'
        for pb in $prebuilts; do
            pkgname="$(echo $pb | sed -e 's,prebuilt/{target_product}/,,' -e 's,/.*,,')"
            pkgfile="$(echo $pb | sed -e 's,prebuilt/{target_product}/,,' -e 's,[^/]*,,')"
            if [[ ! " ${!pkglist} " =~ " ${pkgname} " ]]; then
                # Add pkgname to list
                eval "${pkglist}+=' $pkgname'"
                # Create coresponding dynamic list
                filelist="$(echo $pkgname |tr '-' '_' |tr '.' '_DOT_')"
                declare -a ${filelist}='( )'
            else
                filelist="$(echo $pkgname |tr '-' '_' |tr '.' '_DOT_')"
            fi
            # Add respective file entries to coresponding dynamic list
            eval "${filelist}+=' $pkgfile'"
        done

        # Get Pkg rules of pkgs to be included.
        # echo "${pkglist[@]}: ${!pkglist}"
        for pkgs in "${pkglist[@]}"; do
            local plist=("$(echo ${!pkgs})")
            for pkg in $plist; do
                local comptag="$(get_component_tag_for_pkg "$pkg")"
                local prjname="$(get_project_name_for_pkg "$pkg")"
                local upstream="$(get_project_upstream_for_pkg "$pkg")"
                pbconf="${pbconf}"$'\n\n'"# $pkg"
                pbconf="${pbconf}"$'\n'"$(echo $pkglist |tr '_' '-' |tr '[a-z]' '[A-Z]')_PREBUILT_PACKAGES += \" $pkg \""
                local filelist="$(echo $pkg |tr '-' '_' |tr '.' '_DOT_')" ## Convert - to _
                # echo "${filelist[@]}: ${!filelist}"
                for files in "${filelist[@]}"; do
                    local flist=("$(echo ${!files})")
                    for f in $flist; do
                        pbconf="${pbconf}"$'\n'"PREBUILT_FILES:pn-$(echo $pkg) += \"$f\""
                    done
                done
                pbconf="${pbconf}"$'\n'"PREBUILT_COMPONENT_TAG:pn-$(echo $pkg) = \"$comptag\""
                pbconf="${pbconf}"$'\n'"PREBUILT_PKG_PATH:pn-$(echo $pkg) = \"$(echo $pkg)/$(echo "${comptag##*-}")\""
                pbconf="${pbconf}"$'\n'"PREBUILT_PKG_PRJNAME:pn-$(echo $pkg) = \"$prjname\""
                pbconf="${pbconf}"$'\n'"PREBUILT_PKG_UPSTREAM:pn-$(echo $pkg) = \"$upstream\""
            done
        done
    done

    # Clear and recreate prebuilt conf file.
    pbcfile="${BUILDDIR}/conf/${target}_prebuilts.conf"
    mkdir -p "${pbcfile%/*}" && echo "$pbconf" >> "$pbcfile"
}

get_all_prebuilt_confs() {
    for target in $target_products; do
        create_prebuilt_conf "$target"
    done
}

# set defaults
BUILD_TREE=${WS}
TEMP_DIR="$(mktemp -d)"
MANIFEST="${TEMP_DIR}/c14n_default.xml"
EXTRA_MANIFESTS_PATH="${WS}/EXTRA_MANIFESTS"
EXTRA_MANIFESTS_TEMP_DIR="${TEMP_DIR}/EXTRA_MANIFESTS"

trap "rm -rf $TEMP_DIR" INT TERM EXIT HUP QUIT

if [ ! -d "$BUILD_TREE/.repo" ]; then
   echo "$BUILD_TREE/.repo not found!"
fi

if ! which xmlstarlet > /dev/null; then
   echo "ERROR: xmlstarlet is not installed!"
   echo "Run 'sudo apt-get install xmlstarlet' to install it."
fi

if ! which md5sum > /dev/null; then
    echo "md5sum required to detect changes on manifest file"
fi

if [ -d ${EXTRA_MANIFESTS_PATH} ]; then
    mkdir ${EXTRA_MANIFESTS_TEMP_DIR}
    pushd ${EXTRA_MANIFESTS_PATH}
    for xml in $(ls *.xml | xargs); do
        xmllint --c14n ${xml} > ${EXTRA_MANIFESTS_TEMP_DIR}/${xml}
    done
    popd
fi

(
set -e
CUR_DIR=`pwd` && cd $BUILD_TREE

if [ -f ${BUILDDIR}/conf/manifest.md5sum ]; then
    md5sum -c ${BUILDDIR}/conf/manifest.md5sum 2> /dev/null 1>/dev/null && regen=$?
fi

if [ ${regen:-1} -eq 1 ]; then
    # Remove before regenerating *_prebuilts.conf
    rm -rf ${BUILDDIR}/conf/*_prebuilts.conf || true
    revision=$(cat .repo/manifests/default.xml | \
            xmlstarlet sel -t -m "//default" -v " @revision")

    xmllint --c14n '.repo/manifests/default.xml' > "${MANIFEST}"
    manifests_to_parse="${MANIFEST}"
    if [ -d ${EXTRA_MANIFESTS_TEMP_DIR} ]; then
        manifests_to_parse+=" $(ls ${EXTRA_MANIFESTS_TEMP_DIR}/*.xml | xargs)"
    fi
    echo "manifests_to_parse: $manifests_to_parse"
    is_primary=1
    for xml_file in ${manifests_to_parse}; do
        MANIFEST="${xml_file}"
        target_products=""
        target_varaints=""

        get_target_products
        get_target_varaints
        get_all_prebuilt_confs &
        c=([0]="-" [1]="\\" [2]="|" [3]="/")
        if [ $is_primary -eq 1 ]; then
            echo -n "Changes detected in manifest. Generating prebuilt confs. This may take a few min...${c[0]}"
            is_primary=0
        else
            echo -n "Processing Secondary manifests. Generating prebuilt confs. This may take a few min...${c[0]}"
        fi
        while kill -0 $! 2> /dev/null; do
            for i in "${c[@]}"; do
                echo -ne "\b$i"
                sleep 0.1
            done
        done
    done

    md5sum ${BUILD_TREE}/.repo/manifests/default.xml > ${BUILDDIR}/conf/manifest.md5sum
fi

cd $CUR_DIR
)
