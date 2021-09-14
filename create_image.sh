#!/bin/bash

script_name_full=$(basename "${0}")
script_name_base="${script_name_full%%.*}"
script_file_full=$(readlink -f "${0}")
script_file_base="${script_file_full%%.*}"
script_dir=$(dirname "${script_file_full}")
script_dir_full=$(readlink -f "${script_dir}")


function log_prefix() {
    echo "$(date +%F" "%T)"
}


function log_info() {
    local prefix="$(log_prefix)"
    echo "${prefix} INFO  ${1}"
}


function log_error() {
    local prefix="$(log_prefix)"
    echo "${prefix} ERROR ${1}"
}


function show_help() {
    echo "Script for creating OpenWrt SD card images for Beaglebone Black"
    echo ""
    echo "Usage: ${script_name_full} [options] OPENWRT_VERSION"
    echo "Options:"
    echo "          -d, --download-dir  Directory for downloaded files"
    echo "          -o, --output-dir    Directory for created image files"
    echo "          -t, --temp-dir      Directory for temporary files"
    exit 0
}

function cleanup() {
    if [ -d "${tmp_dir}" ]; then
        rm -rf "${tmp_dir}"
    fi
}

function exit_on_error() {
    log_error "cannot create image"
    cleanup
}

function get_builder () {
    
    log_info "getting builder .."
    
    local file="openwrt-imagebuilder-${openwrt_ver}-omap.Linux-x86_64.tar.xz"
    local url="https://downloads.openwrt.org/releases/${openwrt_ver}/targets/omap/generic/${file}"    


    if [ ! -f "${download_dir}/${file}" ]; then    
        if [ ! -d "${download_dir}" ]; then
            mkdir -p "${download_dir}" || exit_on_error
        fi
        
        wget "${url}" -O "${download_dir}/${file}" || exit_on_error
    fi
    
    if [ ! -d "${tmp_dir}" ]; then
        tmp_dir=$(mktemp -d --suffix "_openwrt_${openwrt_ver}")
    fi
    
    tar xf "${download_dir}/${file}" --one-top-level -C "${tmp_dir}" || exit_on_error
    
    builder_dir="${tmp_dir}/openwrt-imagebuilder-${openwrt_ver}-omap.Linux-x86_64"
    
    log_info "builder directory: ${builder_dir}"

}

function create_bootscr() {
    
    log_info "creating boot script .."
    
    if [ ! -d "${builder_dir}" ]; then
        log_error "builder directory not found"
        exit_on_error
    fi
    
    local boot_script="${script_dir_full}/uboot/mmc-boot.script"
    local bootscr="${builder_dir}/staging_dir/target-arm_cortex-a8+vfpv3_musl_eabi/image/ti_am335x-bone-black/boot.scr"

    mkimage -A arm -T script -c none -d "${boot_script}" "${bootscr}" > /dev/null
}

positional=()
while [[ "${#}" -gt 0 ]]; do
  key="${1}"

  case $key in
    -h|--help)
      show_help
      shift # skip argument
      shift # skip value
      ;;
    -d|--download-dir)
      download_dir="${2}"
      shift # skip argument
      shift # skip value
      ;;
    -o|--output-dir)
      output_dir="${2}"
      shift # skip argument
      shift # skip value
      ;;
    -t|--temp-dir)
      temp_dir="${2}"
      shift # skip argument
      shift # skip value
      ;;
    *)    # unknown option
      positional+=("${1}") # save it in an array for later
      shift # skip argument
      ;;
  esac
done


openwrt_ver="${positional[0]}"

if [ -z "${openwrt_ver}" ]; then
    openwrt_ver="21.02.0"
fi

if [ -z "${download_dir}" ]; then
    download_dir="${script_dir_full}/download"
fi

if [ -z "${output_dir}" ]; then
    output_dir="${script_dir_full}/bin"
fi

if [ ! -d "${output_dir}" ]; then
    mkdir -p "${output_dir}" || exit_on_error
fi

bin_dir="${output_dir}"

packages="luci luci-app-ttyd kmod-ath9k-htc hostapd-mini \
            wpa-supplicant-mini kmod-usb-gadget-eth fdisk lsblk \
            blockdev dosfstools rsync" 

files_dir="${script_dir_full}/files"


get_builder
create_bootscr

make -C "${builder_dir}" image PROFILE="ti_am335x-bone-black" \
    PACKAGES="${packages}" FILES="${files_dir}" BIN_DIR="${bin_dir}"

cleanup
