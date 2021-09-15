# Running OpenWrt on Beaglebone Black

The official [Openwrt images](https://openwrt.org/toh/texas_instruments/beaglebone_black) for Beaglebone Black (BBB) lack some functionalities that many users expect in the default build.

* Network connectivity via the **mimi USB** port.
    * This requires ``kmod-usb-gadget-eth`` package installed and the kernel module ``g_ether`` loaded.
    * The IP address of the USB network interface is ``192.168.100.1``.
    * A DHCP server runs on this network interface making network connections easier.  

* Capability to flash the onboard eMMC storage.
    * This requires accessing OpenWrt terminal via ``ssh`` or ``UART``.
    * Use the following command to flash the eMMC storage.
        **Note: Running this command erases eMMC storage!**
        ```console
        root@OpenWrt:~# /lib/functions/mmc_flasher.sh
        ```
* Force booting from the external SD card by pressing "User Boot" (S2) button.

    The onboard boot ROM searches for the second stage boot loader (SPL or MLO) in the following  order.

    * S2 not pressed - ``MMC1`` (onboard eMMC), ``MMC0`` (SD card), ``UART0``, ``USB0``.
    * S2 pressed - ``SPI0``, ``MMC0`` (SD card), ``USB0``, ``UART0``.

    After the ``MLO`` has loaded the third stage boot loader, ``uBoot`` (``u-boot.img``), ``uBoot`` reads the boot script (``boot.scr``) and the boot environment file (``uEnv.txt``). In most of the builds, ``uBoot`` searches for the ``boot.scr`` and the ``uEnv.txt`` in the ``MMC0`` (SD card) first. This causes the BBB to boot from the SD card regardless of the status of the S2 button.

    We address this problem by reading the status of the S2 button inside the  ``boot.scr`` to determine the boot device.    

* IP address of the onboard Ethernet interface is configured via DHCP instead of static.
* Creating WiFi access points.
    * Requires the packages ``hostapd-mini``, ``wpa-supplicant-mini`` installed.
* Support for popular WiFi chips such as "Atheros AR9271".
    * Requires the package ``kmod-ath9k-htc`` installed.

## Usage

```
./create-image.sh -h
Script for creating OpenWrt SD card images for Beaglebone Black

Usage: create_image.sh [options] OPENWRT_VERSION
Options:
          -d, --download-dir  Directory for downloaded files
                              Default to ./download
          -o, --output-dir    Directory for created image files
                              Default to ./bin
          -t, --temp-dir      Directory for temporary files
```