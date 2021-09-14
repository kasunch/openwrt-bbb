#!/bin/ash

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

if ! id | grep -q root; then
    echo "must be run as root"
    exit
fi


unset root_drive
root_drive=$(lsblk -l | grep "/$" | awk '{print $1}')

if [ "x${root_drive}" = "x" ] ; then
    log_error "script halting, system unrecognized..."
    exit 1
fi

if [ "x${root_drive}" = "xmmcblk0p2" ] ; then
    source="/dev/mmcblk0"
    destination="/dev/mmcblk1"
fi

if [ "x${root_drive}" = "xmmcblk1p2" ] ; then
    source="/dev/mmcblk1"
    destination="/dev/mmcblk0"
fi


flush_cache () {
    sync
    blockdev --flushbufs ${destination}
}

write_failure () {
    log_error "writing to [${destination}] failed..."

    [ -e /proc/$CYLON_PID ]  && kill $CYLON_PID > /dev/null 2>&1

    if [ -e /sys/class/leds/beaglebone\:green\:heartbeat/trigger ] ; then
        echo heartbeat > /sys/class/leds/beaglebone\:green\:heartbeat/trigger
        echo heartbeat > /sys/class/leds/beaglebone\:green\:mmc0/trigger
        echo heartbeat > /sys/class/leds/beaglebone\:green\:usr2/trigger
        echo heartbeat > /sys/class/leds/beaglebone\:green\:usr3/trigger
    fi
    echo "-----------------------------"
    
    flush_cache
    umount ${source}p1 || true
    umount ${destination}p1 || true
    umount ${destination}p2 || true
    
    exit
}

create_partitions () {

    log_info "creating partitions ..."

    flush_cache
    dd if=/dev/zero of=${destination} bs=1M count=108
    sync
    dd if=${destination} of=/dev/null bs=1M count=108
    sync
    
    # Create partions as follows
    # mmcblkX      <size of the EMMC>    
    # --mmcbXk1p1   20M                 W95 FAT32 (LBA)
    # --mmcbXk1p2  <rest of the space>  Linux
    #
    # Also make mmcbXk1p1 partition bootable 
    echo -e "o\nn\np\n1\n\n+20M\nt\n0c\na\nn\np\n2\n\n\np\nw" | fdisk ${destination}
    flush_cache
    
    mkfs.fat -F 16 ${destination}p1
    flush_cache
    
    mkfs.ext4 ${destination}p2
    flush_cache
}


copy_boot () {
    
    log_info "copying uBoot files ..."
    
    mkdir -p /tmp/bootsrc/ || true
    mount ${source}p1 /tmp/bootsrc/ -o ro
    
	mkdir -p /tmp/bootfs/ || true
	mount ${destination}p1 /tmp/bootfs/ -o sync
    
    log_info "copy: bootloader files"
    
	#Make sure the BootLoader gets copied first:
	cp -v /tmp/bootsrc/MLO /tmp/bootfs/MLO || write_failure
	flush_cache

	cp -v /tmp/bootsrc/u-boot.img /tmp/bootfs/u-boot.img || write_failure
	flush_cache
    
    log_info "rsync: /tmp/bootsrc -> /tmp/bootfs/"
    
    rsync -a --exclude="MLO" --exclude="u-boot.img" \
        /tmp/bootsrc/ /tmp/bootfs/ || write_failure
    flush_cache
    
    log_info "umount: /tmp/bootsrc and /tmp/bootfs"
    
    umount /tmp/bootsrc/ || umount -l /tmp/bootsrc/ || write_failure
    umount /tmp/bootfs/ || umount -l /tmp/bootfs/ || write_failure
}

copy_rootfs () {
    
    log_info "copying root file system ..."
    
    mkdir -p /tmp/rootfs/ || true
    mount ${destination}p2 /tmp/rootfs/ -o async,noatime
    
    echo "--> rsync: / -> /tmp/rootfs/"

    rsync -a \
        --exclude="/dev/*" --exclude="/proc/*" --exclude="/sys/*" \
        --exclude="/tmp/*" --exclude="/run/*" --exclude="/mnt/*" \
        --exclude="/media/*" --exclude="/lost+found" --exclude="/boot" \
        --exclude="/var/*" \
        / /tmp/rootfs/ || write_failure
    
    flush_cache
    
    log_info "umount: /tmp/rootfs/"
    
    umount /tmp/rootfs/ || umount -l /tmp/rootfs/ || write_failure
    
    # force writeback of eMMC buffers
    dd if=${destination} of=/dev/null count=100000
}

cylon_leds () {
    if [ -e /sys/class/leds/beaglebone\:green\:heartbeat/trigger ] ; then
        LED0=/sys/class/leds/beaglebone\:green\:heartbeat
        LED1=/sys/class/leds/beaglebone\:green\:mmc0
        LED2=/sys/class/leds/beaglebone\:green\:usr2
        LED3=/sys/class/leds/beaglebone\:green\:usr3
        
        echo none > ${LED0}/trigger
        echo none > ${LED1}/trigger
        echo none > ${LED2}/trigger
        echo none > ${LED3}/trigger

        STATE=1
        while : ; do
            case $STATE in
            1)  echo 255 > ${LED0}/brightness
                echo 0   > ${LED1}/brightness
                STATE=2
                ;;
            2)  echo 255 > ${LED1}/brightness
                echo 0   > ${LED0}/brightness
                STATE=3
                ;;
            3)  echo 255 > ${LED2}/brightness
                echo 0   > ${LED1}/brightness
                STATE=4
                ;;
            4)  echo 255 > ${LED3}/brightness
                echo 0   > ${LED2}/brightness
                STATE=5
                ;;
            5)  echo 255 > ${LED2}/brightness
                echo 0   > ${LED3}/brightness
                STATE=6
                ;;
            6)  echo 255 > ${LED1}/brightness
                echo 0   > ${LED2}/brightness
                STATE=1
                ;;
            *)  echo 255 > ${LED0}/brightness
                echo 0   > ${LED1}/brightness
                STATE=2
                ;;
            esac
            sleep 1
        done
    fi
}

check_running_system () {
    
    log_info "checking running system ..."
    
    log_info "source: ${source}"
    log_info "destination: ${destination}"

    if [ ! -b "${destination}" ] ; then
        log_error "[${destination}] does not exist"
        write_failure
    fi
}

finalise () {
    [ -e /proc/$CYLON_PID ]  && kill $CYLON_PID
    
    if [ -e /sys/class/leds/beaglebone\:green\:heartbeat/trigger ] ; then
        echo default-on > /sys/class/leds/beaglebone\:green\:heartbeat/trigger
        echo default-on > /sys/class/leds/beaglebone\:green\:mmc0/trigger
        echo default-on > /sys/class/leds/beaglebone\:green\:usr2/trigger
        echo default-on > /sys/class/leds/beaglebone\:green\:usr3/trigger
    fi
    
    sync
    
    log_info "--------------------------------"
    log_info "Completed"
    log_info "Shutdown!"
    log_info "--------------------------------"
    halt
}

check_running_system
cylon_leds & CYLON_PID=$!
create_partitions
copy_boot
copy_rootfs
finalise

