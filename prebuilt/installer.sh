#!/sbin/sh
#
##############################################################
# File name       : installer.sh
#
# Description     : Main installation script of BiTGApps
#
# Build Date      : Friday March 15 11:36:43 IST 2019
#
# Updated on      : Tuesday March 03 20:05:36 IST 2020
#
# BiTGApps Author : TheHitMan @ xda-developers
#
# Copyright       : Copyright (C) 2020 TheHitMan7 (Kartik Verma)
#
# License         : SPDX-License-Identifier: GPL-3.0-or-later
##############################################################
# The BiTGApps scripts are free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# These scripts are distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
##############################################################

# Import OUTFD function
ui_print() {
  echo -n -e "ui_print $1\n" >> /proc/self/fd/$OUTFD
  echo -n -e "ui_print\n" >> /proc/self/fd/$OUTFD
}

# Unset predefined environmental variable
recovery_actions() {
  OLD_LD_LIB=$LD_LIBRARY_PATH
  OLD_LD_PRE=$LD_PRELOAD
  OLD_LD_CFG=$LD_CONFIG_FILE
  unset LD_LIBRARY_PATH
  unset LD_PRELOAD
  unset LD_CONFIG_FILE
}

# Restore predefined environmental variable
recovery_cleanup() {
  [ -z $OLD_LD_LIB ] || export LD_LIBRARY_PATH=$OLD_LD_LIB
  [ -z $OLD_LD_PRE ] || export LD_PRELOAD=$OLD_LD_PRE
  [ -z $OLD_LD_CFG ] || export LD_CONFIG_FILE=$OLD_LD_CFG
}

# selinux status
selinux_variable() {
  getenforce >> /cache/bitgapps/selinux.log;
}

# Only support vendor that is outside the system or symlinked in root
vendor_fallback() {
  if [ -f /vendor/build.prop ]; then
    device_vendorpartition=true
    VENDOR=/vendor
  else
    device_vendorpartition=false
  fi;
}

is_mounted() { mount | grep -q " $1 "; }

CONFIG_PROPFILE="/sdcard/bitgapps-config.prop";

profile() {
  BUILD_PROPFILE="$SYSTEM/build.prop";
}

get_file_prop() {
  grep -m1 "^$2=" "$1" | cut -d= -f2
}

get_prop() {
  #check known .prop files using get_file_prop
  for f in $BUILD_PROPFILE $CONFIG_PROPFILE; do
    if [ -e "$f" ]; then
      prop="$(get_file_prop "$f" "$1")"
      if [ -n "$prop" ]; then
        break #if an entry has been found, break out of the loop
      fi;
    fi;
  done
  #if prop is still empty; try to use recovery's built-in getprop method; otherwise output current result
  if [ -z "$prop" ]; then
    getprop "$1" | cut -c1-
  else
    printf "$prop"
  fi;
}

# insert_line <file> <if search string> <before|after> <line match string> <inserted line>
insert_line() {
  local offset line;
  if ! grep -q "$2" $1; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | head -n1 | cut -d: -f1` + offset));
    if [ -f $1 -a "$line" ] && [ "$(wc -l $1 | cut -d\  -f1)" -lt "$line" ]; then
      echo "$5" >> $1;
    else
      sed -i "${line}s;^;${5}\n;" $1;
    fi;
  fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line() {
  if grep -q "$2" $1; then
    local line=$(grep -n "$2" $1 | head -n1 | cut -d: -f1);
    sed -i "${line}s;.*;${3};" $1;
  fi;
}

# remove_line <file> <line match string>
remove_line() {
  if grep -q "$2" $1; then
    local line=$(grep -n "$2" $1 | head -n1 | cut -d: -f1);
    sed -i "${line}d" $1;
  fi;
}

patch_init_Vendor_PM() {
  if [ "$android_sdk" = "$supported_sdk_v28" ]; then
    if [ -f /vendor/etc/init/hw/init.qcom.rc ]; then
      if [ -n "$(cat /vendor/etc/init/hw/init.qcom.rc | grep init.target.rc)" ]; then
        if [ -n "$(cat /vendor/etc/init/hw/init.qcom.rc | grep init.doze64_32.rc)" ]; then
          device_initPatched=true
          echo "ERROR: Vendor init patched already" >> $BOOT;
        else
          device_initPatched=false
          echo "BOOT: Vendor init patched" >> $BOOT;
          # Copy init script to tmp
          cp -f /vendor/etc/init/hw/init.qcom.rc $TMP/init.qcom.rc
          # Append boot script
          mkdir $TMP/outdir
          sed -e "/init.target.rc/a\\import /vendor/etc/init/hw/init.doze64_32.rc" < $TMP/init.qcom.rc >> $TMP/outdir/init.qcom.rc
          rm -rf $TMP/init.rc
          # Install modified kernel init
          rm -rf /vendor/etc/init/hw/init.qcom.rc
          cp -f $TMP/outdir/init.qcom.rc /vendor/etc/init/hw/init.qcom.rc
          rm -rf $TMP/outdir
          chmod 0644 /vendor/etc/init/hw/init.qcom.rc
          # Install boot script
          cp -f $TMP/init.doze64_32.rc /vendor/etc/init/hw/init.doze64_32.rc
          chmod 0644 /vendor/etc/init/hw/init.doze64_32.rc
          chcon -h u:object_r:system_file:s0 "/vendor/etc/init/hw/init.doze64_32.rc";
          # Install function script
          rm -rf $SYSTEM/bin/pm-start.sh
          rm -rf $SYSTEM/bin/pm-stop.sh
          cp -f $TMP/pm-start.sh $SYSTEM/bin/pm-start.sh
          cp -f $TMP/pm-stop.sh $SYSTEM/bin/pm-stop.sh
          chmod 0755 $SYSTEM/bin/pm-start.sh
          chmod 0755 $SYSTEM/bin/pm-stop.sh
          chcon -h u:object_r:system_file:s0 "$SYSTEM/bin/pm-start.sh";
          chcon -h u:object_r:system_file:s0 "$SYSTEM/bin/pm-stop.sh";
          cp -f /vendor/etc/init/hw/init.qcom.rc /cache/bitgapps/init.qcom.rc
        fi;
      else
        echo "ERROR: Unable to find 'init' service" >> $BOOT;
      fi;
    else
      echo "ERROR: Unable to find 'vendor' init" >> $BOOT;
    fi;
  else
    echo "ERROR: Unsupported Android SDK version" >> $BOOT;
  fi;
}

patch_init_Vendor_SQLITE() {
  if [ "$android_sdk" = "$supported_sdk_v29" ] || [ "$android_sdk" = "$supported_sdk_v28" ] || [ "$android_sdk" = "$supported_sdk_v27" ] || [ "$android_sdk" = "$supported_sdk_v25" ];
  then
    if [ -f /vendor/etc/init/hw/init.qcom.rc ]; then
      if [ -n "$(cat /vendor/etc/init/hw/init.qcom.rc | grep init.target.rc)" ]; then
        if [ -n "$(cat /vendor/etc/init/hw/init.qcom.rc | grep init.sqlite64_32.rc)" ]; then
          device_initPatched=true
          echo "ERROR: Vendor init patched already" >> $SQLITE;
        else
          device_initPatched=false
          echo "SQLITE: Vendor init patched" >> $SQLITE;
          # Copy init script to tmp
          cp -f /vendor/etc/init/hw/init.qcom.rc $TMP/init.qcom.rc
          # Append SQLITE script
          mkdir $TMP/outdir
          sed -e "/init.target.rc/a\\import /vendor/etc/init/hw/init.sqlite64_32.rc" < $TMP/init.qcom.rc >> $TMP/outdir/init.qcom.rc
          rm -rf $TMP/init.rc
          # Install modified kernel init
          rm -rf /vendor/etc/init/hw/init.qcom.rc
          cp -f $TMP/outdir/init.qcom.rc /vendor/etc/init/hw/init.qcom.rc
          rm -rf $TMP/outdir
          chmod 0644 /vendor/etc/init/hw/init.qcom.rc
          # Install SQLITE script
          cp -f $TMP/init.sqlite64_32.rc /vendor/etc/init/hw/init.sqlite64_32.rc
          chmod 0644 /vendor/etc/init/hw/init.sqlite64_32.rc
          chcon -h u:object_r:system_file:s0 "/vendor/etc/init/hw/init.sqlite64_32.rc";
          # Install function script
          rm -rf $SYSTEM/bin/sqlite64_32.sh
          rm -rf $SYSTEM/bin/sqlite3
          cp -f $TMP/sqlite64_32.sh $SYSTEM/bin/sqlite64_32.sh
          cp -f $TMP/sqlite3 $SYSTEM/bin/sqlite3
          chmod 0755 $SYSTEM/bin/sqlite64_32.sh
          chmod 0755 $SYSTEM/bin/sqlite3
          chcon -h u:object_r:system_file:s0 "$SYSTEM/bin/sqlite64_32.sh";
          chcon -h u:object_r:system_file:s0 "$SYSTEM/bin/sqlite3";
          cp -f /vendor/etc/init/hw/init.qcom.rc /cache/bitgapps/init.qcom.rc
        fi;
      else
        echo "ERROR: Unable to find 'init' service" >> $SQLITE;
      fi;
    else
      echo "ERROR: Unable to find 'vendor' init" >> $SQLITE;
    fi;
  else
    echo "ERROR: Unsupported Android SDK version" >> $SQLITE;
  fi;
}

# Install packages in sparse mode
set_sparse() {
  # Set sparse format
  send_sparse_1() {
    file_list="$(find "$TMP_SYS/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_SYS/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_SYS/${file}" "$SYSTEM_APP/${file}"
        chmod 0644 "$SYSTEM_APP/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_APP/${dir}";
    done
  }

  send_sparse_2() {
    file_list="$(find "$TMP_PRIV/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_PRIV/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_PRIV/${file}" "$SYSTEM_PRIV_APP/${file}"
        chmod 0644 "$SYSTEM_PRIV_APP/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_PRIV_APP/${dir}";
    done
  }

  send_sparse_3() {
    file_list="$(find "$TMP_FRAMEWORK/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_FRAMEWORK/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_FRAMEWORK/${file}" "$SYSTEM_FRAMEWORK/${file}"
        chmod 0644 "$SYSTEM_FRAMEWORK/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_FRAMEWORK/${dir}";
    done
  }

  send_sparse_4() {
    file_list="$(find "$TMP_LIB/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_LIB/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_LIB/${file}" "$SYSTEM_LIB/${file}"
        chmod 0644 "$SYSTEM_LIB/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_LIB/${dir}";
    done
  }

  send_sparse_5() {
    file_list="$(find "$TMP_LIB64/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_LIB64/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_LIB64/${file}" "$SYSTEM_LIB64/${file}"
        chmod 0644 "$SYSTEM_LIB64/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_LIB64/${dir}";
    done
  }

  send_sparse_6() {
    file_list="$(find "$TMP_CONFIG/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_CONFIG/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_CONFIG/${file}" "$SYSTEM_ETC_CONFIG/${file}"
        chmod 0644 "$SYSTEM_ETC_CONFIG/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_ETC_CONFIG/${dir}";
    done
  }

  send_sparse_7() {
    file_list="$(find "$TMP_DEFAULT_PERM/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_DEFAULT_PERM/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_DEFAULT_PERM/${file}" "$SYSTEM_ETC_DEFAULT/${file}"
        chmod 0644 "$SYSTEM_ETC_DEFAULT/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_ETC_DEFAULT/${dir}";
    done
  }

  send_sparse_8() {
    file_list="$(find "$TMP_G_PREF/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_G_PREF/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_G_PREF/${file}" "$SYSTEM_ETC_PREF/${file}"
        chmod 0644 "$SYSTEM_ETC_PREF/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_ETC_PREF/${dir}";
    done
  }

  send_sparse_9() {
    file_list="$(find "$TMP_G_PERM/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_G_PERM/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_G_PERM/${file}" "$SYSTEM_ETC_PERM/${file}"
        chmod 0644 "$SYSTEM_ETC_PERM/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_ETC_PERM/${dir}";
    done
  }

  send_sparse_10() {
    cp -f $TMP/g.prop $SYSTEM/etc/g.prop
    chmod 0644 $SYSTEM/etc/g.prop
  }

  send_sparse_11() {
    file_list="$(find "$TMP_ADDON/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_ADDON/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_ADDON/${file}" "$SYSTEM_ADDOND/${file}"
        chmod 0644 "$SYSTEM_ADDOND/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_ADDOND/${dir}";
    done
  }

  # execute sparse functions
  exec_sparse_format() {
    send_sparse_1;
    send_sparse_2;
    send_sparse_3;
    send_sparse_4;
    send_sparse_5;
    send_sparse_6;
    send_sparse_7;
    send_sparse_8;
    send_sparse_9;
    send_sparse_10;
  }
  exec_sparse_format;
}

# Function 'send_sparse_12()' must be in a separate call function
set_sparse_excl() {
  # Do not merge 'send_sparse_12()' function in 'set_sparse()' function
  send_sparse_12() {
    file_list="$(find "$TMP_PRIV_SETUP/" -mindepth 1 -type f | cut -d/ -f5-)"
    dir_list="$(find "$TMP_PRIV_SETUP/" -mindepth 1 -type d | cut -d/ -f5-)"
    for file in $file_list; do
        install -D "$TMP_PRIV_SETUP/${file}" "$SYSTEM_PRIV_APP/${file}"
        chmod 0644 "$SYSTEM_PRIV_APP/${file}";
    done
    for dir in $dir_list; do
        chmod 0755 "$SYSTEM_PRIV_APP/${dir}";
    done
  }
  send_sparse_12;
}
# end sparse method

# Static unzip function
unpack_zip() {
  for f in $ZIP; do
    unzip -o "$ZIPFILE" "$f" -d "$TMP";
  done
}

# Set config file property
supported_config="$(get_prop "ro.config.setupwizard")";
supported_target="true";

# Set privileged app Whitelist property
android_flag="$(get_prop "ro.control_privapp_permissions")";
supported_flag_enforce="enforce";
supported_flag_disable="disable";
supported_flag_log="log";
PROPFLAG="ro.control_privapp_permissions";

# Set partition and boot slot property
system_as_root=`getprop ro.build.system_root_image`
active_slot=`getprop ro.boot.slot_suffix`

# Set version check property
on_version_check() {
  android_sdk="$(get_prop "ro.build.version.sdk")";
  supported_sdk="";
  android_version="$(get_prop "ro.build.version.release")";
  supported_version="";
}

# Set product check property
on_product_check() {
  android_product="$(get_prop "ro.product.system.brand")";
  supported_product="samsung";
}

# Set CAF ROM property
on_caf_check () {
  caf_product="$(get_prop "ro.reloaded.device")";
}

# Set platform check property
on_platform_check() {
  # Obsolete build property in use
  device_architecture="$(get_prop "ro.product.cpu.abi")";
}

# Set supported Android SDK Version
on_sdk() {
  supported_sdk_v29="29";
  supported_sdk_v28="28";
  supported_sdk_v27="27";
  supported_sdk_v25="25";
}

# Set supported Android Platform
on_platform() {
  ANDROID_PLATFORM_ARM32="armeabi-v7a";
  ANDROID_PLATFORM_ARM64="arm64-v8a";
}

# Android SDK
check_sdk() {
  ui_print "Checking Android SDK version";
  if [ "$android_sdk" = "$supported_sdk" ]; then
    ui_print "$android_sdk";
    ui_print " ";
  else
    ui_print " ";
    on_abort "Unsupported Android SDK version. Aborting...";
    ui_print " ";
  fi;
}

# Android Version
check_version() {
  ui_print "Checking Android version";
  if [ "$android_version" = "$supported_version" ]; then
    ui_print "$android_version";
    ui_print " ";
  else
    ui_print " ";
    on_abort "Unsupported Android version. Aborting...";
    ui_print " ";
  fi;
}

# Android Platform
check_platform() {
  ui_print "Checking Android platform";
  for targetarch in $ANDROID_PLATFORM_ARM64; do
    if [ "$device_architecture" = "$targetarch" ]; then
      ui_print "$device_architecture";
      ui_print " ";
    else
      ui_print " ";
      on_abort "Unsupported Android platform. Aborting...";
      ui_print " ";
    fi;
  done
}

# Detect A/B partition layout https://source.android.com/devices/tech/ota/ab_updates
# and system-as-root https://source.android.com/devices/bootloader/system-as-root
set_mount() {
  device_abpartition=false
  if [ "$system_as_root" == "true" ]; then
    if [ ! -z "$active_slot" ]; then
      device_abpartition=true
    fi;
  fi;
}

early_mount() {
  umount /data 2>/dev/null;
  if [ -d /system ] && [ -n "$(cat /etc/fstab | grep /system)" ]; then
    umount /system 2>/dev/null;
  fi;
  if [ -d /system_root ] && [ -n "$(cat /etc/fstab | grep /system_root)" ]; then
    umount /system_root 2>/dev/null;
  fi;
  umount /vendor 2>/dev/null;
}

# Mount partitions - RO
mount_part() {
  if ! is_mounted /data; then
    mount /data
  fi;
  if [ -d /system_root ] && [ -n "$(cat /etc/fstab | grep /system_root)" ]; then
    SYSTEM_MOUNT=/system_root
  else
    SYSTEM_MOUNT=/system
  fi;
  mounts=""
  for p in "/cache" "$SYSTEM_MOUNT" "/vendor"; do
    if [ -d "$p" ] && grep -q "$p" "/etc/fstab" && ! mountpoint -q "$p"; then
      mounts="$mounts $p"
    fi;
  done
  for m in $mounts; do
    mount -o ro -t auto "$m"
  done
}

# Re-mount partitions - RW
remount_part() {
  mount -o rw,remount -t auto $SYSTEM_MOUNT
  mount -o rw,remount -t auto /vendor
  mount -o rw,remount -t auto /cache
}

# Set installation layout
system_layout() {
  if [ -f /system_root/system/build.prop ];
  then
    SYSTEM=/system_root/system
  else
    SYSTEM=/system
  fi;
}

# Bind mountpoint /system to /system_root if we have system-as-root
on_AB() {
  if [ -f /system/init.rc ]; then
    system_as_root=true
    [ -L /system_root ] && rm -f /system_root
    mkdir /system_root 2>/dev/null;
    mount --move /system /system_root
    mount -o bind /system_root/system /system
  else
    grep ' / ' /proc/mounts | grep -qv 'rootfs' || grep -q ' /system_root ' /proc/mounts \
    && system_as_root=true || system_as_root=false
  fi;
}

# Print mount status
mount_stat() {
  ui_print "Checking Mount status";
  if [ -f "$SYSTEM/build.prop" ]; then
    ui_print "Mounted";
    ui_print " ";
  else
    ui_print " ";
    mount_abort "Mounting failed. Aborting...";
    ui_print " ";
  fi;
}

cleanup() {
  rm -rf /tmp/unzip
  rm -rf /tmp/zip
}

clean_logs() {
  rm -rf /cache/bitgapps
}

# Generate a separate log file on failed mounting
on_mount_failed() {
  rm -rf /sdcard/bitgapps_debug_failed_logs.tar.gz
  rm -rf /cache/bitgapps
  mkdir /cache/bitgapps
  cd /cache/bitgapps
  cp -f $TMP/recovery.log /cache/bitgapps/recovery.log 2>/dev/null;
  cp -f /etc/fstab /cache/bitgapps/fstab 2>/dev/null;
  selinux_variable;
  tar -cz -f "$TMP/bitgapps_debug_failed_logs.tar.gz" *
  cp -f $TMP/bitgapps_debug_failed_logs.tar.gz /sdcard/bitgapps_debug_failed_logs.tar.gz
  # Checkout log path
  cd /
}

# Generate a separate log file on abort
on_install_failed() {
  rm -rf /sdcard/bitgapps_debug_failed_logs.tar.gz
  rm -rf /cache/bitgapps
  mkdir /cache/bitgapps
  cd /cache/bitgapps
  cp -f $TMP/recovery.log /cache/bitgapps/recovery.log 2>/dev/null;
  selinux_variable;
  cp -f $SYSTEM/build.prop /cache/bitgapps/build.prop 2>/dev/null;
  if [ "$device_vendorpartition" = "true" ]; then
    cp -f $VENDOR/build.prop /cache/bitgapps/build2.prop 2>/dev/null;
  fi;
  cp -f /system_root/system/etc/prop.default /cache/bitgapps/prop.default 2>/dev/null;
  cp -f /sdcard/bitgapps-config.prop /cache/bitgapps/bitgapps-config.prop 2>/dev/null;
  tar -cz -f "$TMP/bitgapps_debug_failed_logs.tar.gz" *
  cp -f $TMP/bitgapps_debug_failed_logs.tar.gz /sdcard/bitgapps_debug_failed_logs.tar.gz
  # Checkout log path
  cd /
}

# log
on_install_complete() {
  rm -rf /sdcard/bitgapps_debug_complete_logs.tar.gz
  cd /cache/bitgapps
  cp -f $TMP/recovery.log /cache/bitgapps/recovery.log 2>/dev/null;
  cp -f $SYSTEM/build.prop /cache/bitgapps/build.prop 2>/dev/null;
  if [ "$device_vendorpartition" = "true" ]; then
    cp -f $VENDOR/build.prop /cache/bitgapps/build2.prop 2>/dev/null;
  fi;
  cp -f /system_root/system/etc/prop.default /cache/bitgapps/prop.default 2>/dev/null;
  cp -f /sdcard/bitgapps-config.prop /cache/bitgapps/bitgapps-config.prop 2>/dev/null;
  tar -cz -f "$TMP/bitgapps_debug_complete_logs.tar.gz" *
  cp -f $TMP/bitgapps_debug_complete_logs.tar.gz /sdcard/bitgapps_debug_complete_logs.tar.gz
  # Checkout log path
  cd /
}

unmount_all() {
  ui_print " ";
  if [ "$device_abpartition" = "true" ]; then
    mount -o ro $SYSTEM_MOUNT
  else
    umount $SYSTEM_MOUNT
  fi;
  if [ "$device_vendorpartition" = "true" ]; then
    if [ "$device_abpartition" = "true" ]; then
      mount -o ro $VENDOR
    fi;
    umount $VENDOR
  fi;
}

on_installed() {
  selinux_variable;
  on_install_complete;
  clean_logs;
  cleanup;
  recovery_cleanup;
  unmount_all;
}

mount_abort() {
  ui_print "$*";
  on_mount_failed;
  clean_logs;
  cleanup;
  recovery_cleanup;
  unmount_all;
  exit 1;
}

on_abort() {
  ui_print "$*";
  on_install_failed;
  clean_logs;
  cleanup;
  recovery_cleanup;
  unmount_all;
  exit 1;
}

print_build_info() {
  ui_print "Done";
  ui_print " ";
  ui_print "****************** Software *******************";
  ui_print "Custom GApps    : $PKG";
  ui_print "Android version : $VER";
  ui_print "Android Arch    : $ARCH";
  ui_print "SDK version     : $VER_SDK";
  ui_print "Build date      : $DATE";
  ui_print "Build ID        : $ID";
  ui_print "Developed By    : $AUTH";
  ui_print "***********************************************";
  ui_print " ";
}

# Set build defaults
PKG="BiTGApps"
VER=""
ARCH=""
DATE=""
ID=""
VER_SDK=""
AUTH="TheHitMan @ xda-developers"

# Set package defaults
TMP="/tmp";
ZIP_FILE="/tmp/zip";
# Create temporary unzip directory
mkdir /tmp/unzip
chmod 0755 /tmp/unzip
# Create temporary outfile directory
mkdir /tmp/out
chmod 0755 /tmp/out
# Create temporary links
UNZIP_DIR="/tmp/unzip";
TMP_ADDON="$UNZIP_DIR/tmp_addon";
TMP_SYS="$UNZIP_DIR/tmp_sys";
TMP_SYS_ROOT="$UNZIP_DIR/tmp_sys_root";
TMP_PRIV="$UNZIP_DIR/tmp_priv";
TMP_PRIV_ROOT="$UNZIP_DIR/tmp_priv_root";
TMP_PRIV_SETUP="$UNZIP_DIR/tmp_priv_setup";
TMP_LIB="$UNZIP_DIR/tmp_lib";
TMP_LIB64="$UNZIP_DIR/tmp_lib64";
TMP_FRAMEWORK="$UNZIP_DIR/tmp_framework";
TMP_CONFIG="$UNZIP_DIR/tmp_config";
TMP_DEFAULT_PERM="$UNZIP_DIR/tmp_default";
TMP_G_PERM="$UNZIP_DIR/tmp_perm";
TMP_G_PREF="$UNZIP_DIR/tmp_pref";
TMP_PERM_ROOT="$UNZIP_DIR/tmp_perm_root";
# Set logging
LOG="/cache/bitgapps/installation.log";
config_log="/cache/bitgapps/config-installation.log";
whitelist="/cache/bitgapps/whitelist.log";
SQLITE="/cache/bitgapps/sqlite.log";
ZIPALIGN_LOG="/cache/bitgapps/zipalign.log";
ZIPALIGN_TOOL="/tmp/zipalign";
ZIPALIGN_OUTFILE="/tmp/out";
sdk_v29="/cache/bitgapps/sdk_v29.log";
sdk_v28="/cache/bitgapps/sdk_v28.log";
sdk_v27="/cache/bitgapps/sdk_v27.log";
sdk_v25="/cache/bitgapps/sdk_v25.log";
LINKER="/cache/bitgapps/lib_symlink.log";
BOOT="/cache/bitgapps/boot.log";
PARTITION="/cache/bitgapps/vendor.log";
CTS_PATCH="/cache/bitgapps/cts.log";
CONFIG="/cache/bitgapps/bitgapps-config.log";
# CTS defaults
CTS_DEFAULT_SYSTEM_BUILD_FINGERPRINT="ro.build.fingerprint=";
CTS_DEFAULT_SYSTEM_BUILD_SEC_PATCH="ro.build.version.security_patch=";
CTS_DEFAULT_VENDOR_BUILD_FINGERPRINT="ro.vendor.build.fingerprint=";
CTS_DEFAULT_VENDOR_BUILD_BOOTIMAGE="ro.bootimage.build.fingerprint=";
# CTS patch
CTS_SYSTEM_BUILD_FINGERPRINT="ro.build.fingerprint=google/walleye/walleye:10/QQ1A.200205.002/6084386:user/release-keys";
CTS_SYSTEM_BUILD_SEC_PATCH="ro.build.version.security_patch=2020-02-05";
CTS_VENDOR_BUILD_FINGERPRINT="ro.vendor.build.fingerprint=google/walleye/walleye:10/QQ1A.200205.002/6084386:user/release-keys";
CTS_VENDOR_BUILD_BOOTIMAGE="ro.bootimage.build.fingerprint=google/walleye/walleye:10/QQ1A.200205.002/6084386:user/release-keys";

# Set pathmap
system_pathmap() {
  SYSTEM_ADDOND="$SYSTEM/addon.d";
  SYSTEM_APP="$SYSTEM/app";
  SYSTEM_PRIV_APP="$SYSTEM/priv-app";
  SYSTEM_ETC_CONFIG="$SYSTEM/etc/sysconfig";
  SYSTEM_ETC_DEFAULT="$SYSTEM/etc";
  SYSTEM_ETC_PERM="$SYSTEM/etc/permissions";
  SYSTEM_ETC_PREF="$SYSTEM/etc";
  SYSTEM_FRAMEWORK="$SYSTEM/framework";
  SYSTEM_LIB="$SYSTEM/lib";
  SYSTEM_LIB64="$SYSTEM/lib64";
}

# Create temporary log directory
logd() {
  mkdir /cache/bitgapps
  chmod 0755 /cache/bitgapps
}

# Create installation components
mk_component() {
  echo "-----------------------------------" >> $LOG;
  echo " --- BiTGApps Installation Log --- " >> $LOG;
  echo "             Start at              " >> $LOG;
  echo "        $( date +"%m-%d-%Y %H:%M:%S" )" >> $LOG;
  echo "-----------------------------------" >> $LOG;
  echo " " >> $LOG;
  echo "-----------------------------------" >> $LOG;
  if [ -d /cache/bitgapps ]; then
    echo "- Log directory found in :" /cache >> $LOG;
  else
    echo "- Log directory not found in :" /cache >> $LOG;
  fi;
  echo "-----------------------------------" >> $LOG;
  if [ -d "$UNZIP_DIR" ]; then
    echo "- Unzip directory found in :" $TMP >> $LOG;
    echo "- Creating components in :" $TMP >> $LOG;
    mkdir $UNZIP_DIR/tmp_addon
    mkdir $UNZIP_DIR/tmp_sys
    mkdir $UNZIP_DIR/tmp_sys_root
    mkdir $UNZIP_DIR/tmp_priv
    mkdir $UNZIP_DIR/tmp_priv_root
    mkdir $UNZIP_DIR/tmp_priv_setup
    mkdir $UNZIP_DIR/tmp_lib
    mkdir $UNZIP_DIR/tmp_lib64
    mkdir $UNZIP_DIR/tmp_framework
    mkdir $UNZIP_DIR/tmp_config
    mkdir $UNZIP_DIR/tmp_default
    mkdir $UNZIP_DIR/tmp_perm
    mkdir $UNZIP_DIR/tmp_pref
    mkdir $UNZIP_DIR/tmp_perm_root
    chmod 0755 $UNZIP_DIR
    chmod 0755 $UNZIP_DIR/tmp_addon
    chmod 0755 $UNZIP_DIR/tmp_sys
    chmod 0755 $UNZIP_DIR/tmp_sys_root
    chmod 0755 $UNZIP_DIR/tmp_priv
    chmod 0755 $UNZIP_DIR/tmp_priv_root
    chmod 0755 $UNZIP_DIR/tmp_priv_setup
    chmod 0755 $UNZIP_DIR/tmp_lib
    chmod 0755 $UNZIP_DIR/tmp_lib64
    chmod 0755 $UNZIP_DIR/tmp_framework
    chmod 0755 $UNZIP_DIR/tmp_config
    chmod 0755 $UNZIP_DIR/tmp_default
    chmod 0755 $UNZIP_DIR/tmp_perm
    chmod 0755 $UNZIP_DIR/tmp_pref
    chmod 0755 $UNZIP_DIR/tmp_perm_root
  else
    echo "- Unzip directory not found in :" $TMP >> $LOG;
  fi;
}

# Remove pre-installed system files
pre_installed_v29() {
  if [ "$android_sdk" = "$supported_sdk_v29" ]; then
    rm -rf $SYSTEM_APP/GoogleCalendarSyncAdapter
    rm -rf $SYSTEM_APP/GoogleContactsSyncAdapter
    rm -rf $SYSTEM_APP/ExtShared
    rm -rf $SYSTEM_APP/GoogleExtShared
    rm -rf $SYSTEM_APP/MarkupGoogle
    rm -rf $SYSTEM_APP/SoundPickerPrebuilt
    rm -rf $SYSTEM/product/app/MarkupGoogle
    rm -rf $SYSTEM/product/app/SoundPickerPrebuilt
    rm -rf $SYSTEM_PRIV_APP/CarrierSetup
    rm -rf $SYSTEM_PRIV_APP/ConfigUpdater
    rm -rf $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt
    rm -rf $SYSTEM_PRIV_APP/ExtServices
    rm -rf $SYSTEM_PRIV_APP/GoogleExtServices
    rm -rf $SYSTEM_PRIV_APP/GoogleServicesFramework
    rm -rf $SYSTEM_PRIV_APP/Phonesky
    rm -rf $SYSTEM_PRIV_APP/PrebuiltGmsCore
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.maps.jar
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.media.effects.jar
    rm -rf $SYSTEM_LIB/libsketchology_native.so
    rm -rf $SYSTEM/product/lib/libsketchology_native.so
    rm -rf $SYSTEM_LIB64/libjni_latinimegoogle.so
    rm -rf $SYSTEM_LIB64/libsketchology_native.so
    rm -rf $SYSTEM/product/lib64/libsketchology_native.so
    rm -rf $SYSTEM_ETC_CONFIG/dialer_experience.xml
    rm -rf $SYSTEM_ETC_CONFIG/google.xml
    rm -rf $SYSTEM_ETC_CONFIG/google_build.xml
    rm -rf $SYSTEM_ETC_CONFIG/google_exclusives_enable.xml
    rm -rf $SYSTEM_ETC_CONFIG/google-hiddenapi-package-whitelist.xml
    rm -rf $SYSTEM_ETC_DEFAULT/default-permissions
    rm -rf $SYSTEM_ETC_PERM/com.google.android.dialer.support.xml
    rm -rf $SYSTEM_ETC_PERM/com.google.android.maps.xml
    rm -rf $SYSTEM_ETC_PERM/com.google.android.media.effects.xml
    rm -rf $SYSTEM_ETC_PERM/privapp-permissions-google.xml
    rm -rf $SYSTEM_ETC_PERM/split-permissions-google.xml
    rm -rf $SYSTEM_ETC_PREF/preferred-apps
    rm -rf $SYSTEM/etc/g.prop
  fi;
}

pre_installed_v28() {
  if [ "$android_sdk" = "$supported_sdk_v28" ]; then
    rm -rf $SYSTEM_APP/FaceLock
    rm -rf $SYSTEM_APP/GoogleCalendarSyncAdapter
    rm -rf $SYSTEM_APP/GoogleContactsSyncAdapter
    rm -rf $SYSTEM_APP/ExtShared
    rm -rf $SYSTEM_APP/GoogleExtShared
    rm -rf $SYSTEM_APP/MarkupGoogle
    rm -rf $SYSTEM_APP/SoundPickerPrebuilt
    rm -rf $SYSTEM_PRIV_APP/CarrierSetup
    rm -rf $SYSTEM_PRIV_APP/ConfigUpdater
    rm -rf $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt
    rm -rf $SYSTEM_PRIV_APP/ExtServices
    rm -rf $SYSTEM_PRIV_APP/GoogleExtServices
    rm -rf $SYSTEM_PRIV_APP/GoogleServicesFramework
    rm -rf $SYSTEM_PRIV_APP/Phonesky
    rm -rf $SYSTEM_PRIV_APP/PrebuiltGmsCorePi
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.maps.jar
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.media.effects.jar
    rm -rf $SYSTEM_LIB/libfilterpack_facedetect.so
    rm -rf $SYSTEM_LIB/libfrsdk.so
    rm -rf $SYSTEM_LIB64/libfacenet.so
    rm -rf $SYSTEM_LIB64/libfilterpack_facedetect.so
    rm -rf $SYSTEM_LIB64/libfrsdk.so
    rm -rf $SYSTEM_LIB64/libjni_latinimegoogle.so
    rm -rf $SYSTEM_LIB64/libsketchology_native.so
    rm -rf $SYSTEM_ETC_CONFIG/dialer_experience.xml
    rm -rf $SYSTEM_ETC_CONFIG/google.xml
    rm -rf $SYSTEM_ETC_CONFIG/google_build.xml
    rm -rf $SYSTEM_ETC_CONFIG/google_exclusives_enable.xml
    rm -rf $SYSTEM_ETC_CONFIG/google-hiddenapi-package-whitelist.xml
    rm -rf $SYSTEM_ETC_DEFAULT/default-permissions
    rm -rf $SYSTEM_ETC_PERM/com.google.android.dialer.support.xml
    rm -rf $SYSTEM_ETC_PERM/com.google.android.maps.xml
    rm -rf $SYSTEM_ETC_PERM/com.google.android.media.effects.xml
    rm -rf $SYSTEM_ETC_PERM/privapp-permissions-google.xml
    rm -rf $SYSTEM_ETC_PREF/preferred-apps
    rm -rf $SYSTEM/etc/g.prop
  fi;
}

pre_installed_v27() {
  if [ "$android_sdk" = "$supported_sdk_v27" ]; then
    rm -rf $SYSTEM_APP/FaceLock
    rm -rf $SYSTEM_APP/GoogleCalendarSyncAdapter
    rm -rf $SYSTEM_APP/GoogleContactsSyncAdapter
    rm -rf $SYSTEM_APP/ExtShared
    rm -rf $SYSTEM_APP/GoogleExtShared
    rm -rf $SYSTEM_PRIV_APP/CarrierSetup
    rm -rf $SYSTEM_PRIV_APP/ConfigUpdater
    rm -rf $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt
    rm -rf $SYSTEM_PRIV_APP/ExtServices
    rm -rf $SYSTEM_PRIV_APP/GoogleExtServices
    rm -rf $SYSTEM_PRIV_APP/GoogleServicesFramework
    rm -rf $SYSTEM_PRIV_APP/Phonesky
    rm -rf $SYSTEM_PRIV_APP/PrebuiltGmsCorePix
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.maps.jar
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.media.effects.jar
    rm -rf $SYSTEM_LIB/libfilterpack_facedetect.so
    rm -rf $SYSTEM_LIB/libfrsdk.so
    rm -rf $SYSTEM_LIB64/libfacenet.so
    rm -rf $SYSTEM_LIB64/libfilterpack_facedetect.so
    rm -rf $SYSTEM_LIB64/libfrsdk.so
    rm -rf $SYSTEM_LIB64/libjni_latinimegoogle.so
    rm -rf $SYSTEM_ETC_CONFIG/dialer_experience.xml
    rm -rf $SYSTEM_ETC_CONFIG/google.xml
    rm -rf $SYSTEM_ETC_CONFIG/google_build.xml
    rm -rf $SYSTEM_ETC_CONFIG/google_exclusives_enable.xml
    rm -rf $SYSTEM_ETC_DEFAULT/default-permissions
    rm -rf $SYSTEM_ETC_PERM/com.google.android.dialer.support.xml
    rm -rf $SYSTEM_ETC_PERM/com.google.android.maps.xml
    rm -rf $SYSTEM_ETC_PERM/com.google.android.media.effects.xml
    rm -rf $SYSTEM_ETC_PERM/privapp-permissions-google.xml
    rm -rf $SYSTEM_ETC_PREF/preferred-apps
    rm -rf $SYSTEM/etc/g.prop
  fi;
}

pre_installed_v25() {
  if [ "$android_sdk" = "$supported_sdk_v25" ]; then
    rm -rf $SYSTEM_APP/FaceLock
    rm -rf $SYSTEM_APP/GoogleCalendarSyncAdapter
    rm -rf $SYSTEM_APP/GoogleContactsSyncAdapter
    rm -rf $SYSTEM_APP/ExtShared
    rm -rf $SYSTEM_APP/GoogleExtShared
    rm -rf $SYSTEM_PRIV_APP/ConfigUpdater
    rm -rf $SYSTEM_PRIV_APP/ExtServices
    rm -rf $SYSTEM_PRIV_APP/GoogleExtServices
    rm -rf $SYSTEM_PRIV_APP/GoogleLoginService
    rm -rf $SYSTEM_PRIV_APP/GoogleServicesFramework
    rm -rf $SYSTEM_PRIV_APP/Phonesky
    rm -rf $SYSTEM_PRIV_APP/PrebuiltGmsCore
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.maps.jar
    rm -rf $SYSTEM_FRAMEWORK/com.google.android.media.effects.jar
    rm -rf $SYSTEM_LIB/libfilterpack_facedetect.so
    rm -rf $SYSTEM_LIB/libfrsdk.so
    rm -rf $SYSTEM_LIB64/libfacenet.so
    rm -rf $SYSTEM_LIB64/libfilterpack_facedetect.so
    rm -rf $SYSTEM_LIB64/libfrsdk.so
    rm -rf $SYSTEM_LIB64/libjni_latinimegoogle.so
    rm -rf $SYSTEM_ETC_CONFIG/dialer_experience.xml
    rm -rf $SYSTEM_ETC_CONFIG/google.xml
    rm -rf $SYSTEM_ETC_CONFIG/google_build.xml
    rm -rf $SYSTEM_ETC_CONFIG/google_exclusives_enable.xml
    rm -rf $SYSTEM_ETC_DEFAULT/default-permissions
    rm -rf $SYSTEM_ETC_PERM/com.google.android.dialer.support.xml
    rm -rf $SYSTEM_ETC_PERM/com.google.android.maps.xml
    rm -rf $SYSTEM_ETC_PERM/com.google.android.media.effects.xml
    rm -rf $SYSTEM_ETC_PREF/preferred-apps
    rm -rf $SYSTEM/etc/g.prop
  fi;
}

# Set installation functions for Android SDK 29
sdk_v29_install() {
  if [ "$android_sdk" = "$supported_sdk_v29" ]; then
    # Set default packages
    ZIP="
      zip/core/priv_app_CarrierSetup.tar.xz
      zip/core/priv_app_ConfigUpdater.tar.xz
      zip/core/priv_app_GmsCoreSetupPrebuilt.tar.xz
      zip/core/priv_app_GoogleExtServices.tar.xz
      zip/core/priv_app_GoogleServicesFramework.tar.xz
      zip/core/priv_app_Phonesky.tar.xz
      zip/core/priv_app_PrebuiltGmsCore.tar.xz
      zip/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz
      zip/sys/sys_app_GoogleContactsSyncAdapter.tar.xz
      zip/sys/sys_app_GoogleExtShared.tar.xz
      zip/sys/sys_app_MarkupGoogle.tar.xz
      zip/sys/sys_app_SoundPickerPrebuilt.tar.xz
      zip/sys_Config_Permission.tar.xz
      zip/sys_Default_Permission.tar.xz
      zip/sys_Framework.tar.xz
      zip/sys_Lib.tar.xz
      zip/sys_Lib64.tar.xz
      zip/sys_Permissions.tar.xz
      zip/sys_Pref_Permission.tar.xz"

    # Unzip system files from installer
    unpack_zip;

    # Unpack system files
    extract_app() {
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack SYS-APP Files" >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_MarkupGoogle.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_SoundPickerPrebuilt.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_MarkupGoogle.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_SoundPickerPrebuilt.tar.xz -C $TMP_SYS;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack PRIV-APP Files" >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_CarrierSetup.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_ConfigUpdater.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GmsCoreSetupPrebuilt.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GoogleExtServices.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_Phonesky.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_PrebuiltGmsCore.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/core/priv_app_CarrierSetup.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_ConfigUpdater.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GmsCoreSetupPrebuilt.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GoogleExtServices.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_Phonesky.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_PrebuiltGmsCore.tar.xz -C $TMP_PRIV;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack Framework Files" >> $LOG;
      tar tvf $ZIP_FILE/sys_Framework.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Framework.tar.xz -C $TMP_FRAMEWORK;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Lib" >> $LOG;
      tar tvf $ZIP_FILE/sys_Lib.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Lib.tar.xz -C $TMP_LIB;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Lib64" >> $LOG;
      tar tvf $ZIP_FILE/sys_Lib64.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Lib64.tar.xz -C $TMP_LIB64;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Files" >> $LOG;
      tar tvf $ZIP_FILE/sys_Config_Permission.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Default_Permission.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Permissions.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Pref_Permission.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Config_Permission.tar.xz -C $TMP_CONFIG;
      tar -xf $ZIP_FILE/sys_Default_Permission.tar.xz -C $TMP_DEFAULT_PERM;
      tar -xf $ZIP_FILE/sys_Permissions.tar.xz -C $TMP_G_PERM;
      tar -xf $ZIP_FILE/sys_Pref_Permission.tar.xz -C $TMP_G_PREF;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Installation Complete" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "Finish at $( date +"%m-%d-%Y %H:%M:%S" )" >> $LOG;
      echo "-----------------------------------" >> $LOG;
    }

    # Set selinux context
    selinux_context_s1() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/MarkupGoogle";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/SoundPickerPrebuilt";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk";
    }

    selinux_context_sp2() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/CarrierSetup";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCore";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky/Phonesky.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk";
    }

    selinux_context_sf3() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.maps.jar";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.media.effects.jar";
    }

    selinux_context_sl4() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB/libsketchology_native.so";
    }

    selinux_context_sl5() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libjni_latinimegoogle.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libsketchology_native.so";
    }

    selinux_context_se6() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/default-permissions.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/opengapps-permissions.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.dialer.support.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.maps.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.media.effects.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/privapp-permissions-google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/split-permissions-google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps/google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/dialer_experience.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_build.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_exclusives_enable.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google-hiddenapi-package-whitelist.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM/etc/g.prop";
    }
    # end selinux method

    # APK optimization using zipalign tool
    apk_opt() {
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk $ZIPALIGN_OUTFILE/GoogleCalendarSyncAdapter.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk $ZIPALIGN_OUTFILE/GoogleContactsSyncAdapter.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk $ZIPALIGN_OUTFILE/GoogleExtShared.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk $ZIPALIGN_OUTFILE/MarkupGoogle.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk $ZIPALIGN_OUTFILE/SoundPickerPrebuilt.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk $ZIPALIGN_OUTFILE/CarrierSetup.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk $ZIPALIGN_OUTFILE/ConfigUpdater.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk $ZIPALIGN_OUTFILE/GmsCoreSetupPrebuilt.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk $ZIPALIGN_OUTFILE/GoogleExtServices.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk $ZIPALIGN_OUTFILE/GoogleServicesFramework.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk $ZIPALIGN_OUTFILE/Phonesky.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk $ZIPALIGN_OUTFILE/PrebuiltGmsCore.apk >> $ZIPALIGN_LOG;
    }

    pre_opt() {
      rm -rf $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      rm -rf $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      rm -rf $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      rm -rf $SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk
      rm -rf $SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk
      rm -rf $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk
      rm -rf $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      rm -rf $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
      rm -rf $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      rm -rf $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      rm -rf $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      rm -rf $SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk
    }

    add_opt() {
      cp -f $ZIPALIGN_OUTFILE/GoogleCalendarSyncAdapter.apk $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleContactsSyncAdapter.apk $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleExtShared.apk $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      cp -f $ZIPALIGN_OUTFILE/MarkupGoogle.apk $SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk
      cp -f $ZIPALIGN_OUTFILE/SoundPickerPrebuilt.apk $SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk
      cp -f $ZIPALIGN_OUTFILE/CarrierSetup.apk $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk
      cp -f $ZIPALIGN_OUTFILE/ConfigUpdater.apk $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      cp -f $ZIPALIGN_OUTFILE/GmsCoreSetupPrebuilt.apk $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleExtServices.apk $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleServicesFramework.apk $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      cp -f $ZIPALIGN_OUTFILE/Phonesky.apk $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      cp -f $ZIPALIGN_OUTFILE/PrebuiltGmsCore.apk $SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk
    }

    perm_opt() {
      chmod 0644 $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      chmod 0644 $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      chmod 0644 $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      chmod 0644 $SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk
      chmod 0644 $SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk
      chmod 0644 $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk
      chmod 0644 $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      chmod 0644 $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
      chmod 0644 $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      chmod 0644 $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      chmod 0644 $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      chmod 0644 $SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk
    }
    # end opt method

    # execute installation functions
    sdk_v29() {
      extract_app;
      set_sparse;
      selinux_context_s1;
      selinux_context_sp2;
      selinux_context_sf3;
      selinux_context_sl4;
      selinux_context_sl5;
      selinux_context_se6;
      apk_opt;
      pre_opt;
      add_opt;
      perm_opt;
      # Re-run selinux functions for optimized APKs
      selinux_context_s1;
      selinux_context_sp2;
      # end selinux functions
    }
    sdk_v29;
    # Print installed files to sdk log
    cat $LOG >> $sdk_v29;
  else
    echo "Target Android SDK Version : $android_sdk" >> $sdk_v29;
  fi;
}

# Set installation functions for Android SDK 28
sdk_v28_install() {
  if [ "$android_sdk" = "$supported_sdk_v28" ]; then
    # Set default packages
    ZIP="
      zip/core/priv_app_CarrierSetup.tar.xz
      zip/core/priv_app_ConfigUpdater.tar.xz
      zip/core/priv_app_GmsCoreSetupPrebuilt.tar.xz
      zip/core/priv_app_GoogleExtServices.tar.xz
      zip/core/priv_app_GoogleServicesFramework.tar.xz
      zip/core/priv_app_Phonesky.tar.xz
      zip/core/priv_app_PrebuiltGmsCorePi.tar.xz
      zip/sys/sys_app_FaceLock.tar.xz
      zip/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz
      zip/sys/sys_app_GoogleContactsSyncAdapter.tar.xz
      zip/sys/sys_app_GoogleExtShared.tar.xz
      zip/sys/sys_app_MarkupGoogle.tar.xz
      zip/sys/sys_app_SoundPickerPrebuilt.tar.xz
      zip/sys_Config_Permission.tar.xz
      zip/sys_Default_Permission.tar.xz
      zip/sys_Framework.tar.xz
      zip/sys_Lib.tar.xz
      zip/sys_Lib64.tar.xz
      zip/sys_Permissions.tar.xz
      zip/sys_Pref_Permission.tar.xz"

    # Unzip system files from installer
    unpack_zip;

    # Unpack system files
    extract_app() {
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack SYS-APP Files" >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_FaceLock.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_MarkupGoogle.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_SoundPickerPrebuilt.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys/sys_app_FaceLock.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_MarkupGoogle.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_SoundPickerPrebuilt.tar.xz -C $TMP_SYS;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack PRIV-APP Files" >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_CarrierSetup.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_ConfigUpdater.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GmsCoreSetupPrebuilt.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GoogleExtServices.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_Phonesky.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_PrebuiltGmsCorePi.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/core/priv_app_CarrierSetup.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_ConfigUpdater.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GmsCoreSetupPrebuilt.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GoogleExtServices.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_Phonesky.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_PrebuiltGmsCorePi.tar.xz -C $TMP_PRIV;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack Framework Files" >> $LOG;
      tar tvf $ZIP_FILE/sys_Framework.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Framework.tar.xz -C $TMP_FRAMEWORK;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Lib" >> $LOG;
      tar tvf $ZIP_FILE/sys_Lib.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Lib.tar.xz -C $TMP_LIB;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Lib64" >> $LOG;
      tar tvf $ZIP_FILE/sys_Lib64.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Lib64.tar.xz -C $TMP_LIB64;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Files" >> $LOG;
      tar tvf $ZIP_FILE/sys_Config_Permission.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Default_Permission.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Permissions.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Pref_Permission.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Config_Permission.tar.xz -C $TMP_CONFIG;
      tar -xf $ZIP_FILE/sys_Default_Permission.tar.xz -C $TMP_DEFAULT_PERM;
      tar -xf $ZIP_FILE/sys_Permissions.tar.xz -C $TMP_G_PERM;
      tar -xf $ZIP_FILE/sys_Pref_Permission.tar.xz -C $TMP_G_PREF;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Installation Complete" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "Finish at $( date +"%m-%d-%Y %H:%M:%S" )" >> $LOG;
      echo "-----------------------------------" >> $LOG;
    }

    # Set selinux context
    selinux_context_s1() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/FaceLock";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/MarkupGoogle";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/SoundPickerPrebuilt";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/FaceLock/FaceLock.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk";
    }

    selinux_context_sp2() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/CarrierSetup";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCorePi";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky/Phonesky.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCorePi/PrebuiltGmsCorePi.apk";
    }

    selinux_context_sf3() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.maps.jar";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.media.effects.jar";
    }

    selinux_context_sl4() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB/libfilterpack_facedetect.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB/libfrsdk.so";
    }

    selinux_context_sl5() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libfacenet.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libfilterpack_facedetect.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libfrsdk.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libjni_latinimegoogle.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libsketchology_native.so";
    }

    selinux_context_se6() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/default-permissions.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/opengapps-permissions.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.dialer.support.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.maps.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.media.effects.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/privapp-permissions-google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps/google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/dialer_experience.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_build.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_exclusives_enable.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google-hiddenapi-package-whitelist.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM/etc/g.prop";
    }
    # end selinux method

    # APK optimization using zipalign tool
    apk_opt() {
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/FaceLock/FaceLock.apk $ZIPALIGN_OUTFILE/FaceLock.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk $ZIPALIGN_OUTFILE/GoogleCalendarSyncAdapter.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk $ZIPALIGN_OUTFILE/GoogleContactsSyncAdapter.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk $ZIPALIGN_OUTFILE/GoogleExtShared.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk $ZIPALIGN_OUTFILE/MarkupGoogle.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk $ZIPALIGN_OUTFILE/SoundPickerPrebuilt.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk $ZIPALIGN_OUTFILE/CarrierSetup.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk $ZIPALIGN_OUTFILE/ConfigUpdater.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk $ZIPALIGN_OUTFILE/GmsCoreSetupPrebuilt.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk $ZIPALIGN_OUTFILE/GoogleExtServices.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk $ZIPALIGN_OUTFILE/GoogleServicesFramework.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk $ZIPALIGN_OUTFILE/Phonesky.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/PrebuiltGmsCorePi/PrebuiltGmsCorePi.apk $ZIPALIGN_OUTFILE/PrebuiltGmsCorePi.apk >> $ZIPALIGN_LOG;
    }

    pre_opt() {
      rm -rf $SYSTEM_APP/FaceLock/FaceLock.apk
      rm -rf $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      rm -rf $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      rm -rf $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      rm -rf $SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk
      rm -rf $SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk
      rm -rf $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk
      rm -rf $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      rm -rf $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
      rm -rf $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      rm -rf $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      rm -rf $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      rm -rf $SYSTEM_PRIV_APP/PrebuiltGmsCorePi/PrebuiltGmsCorePi.apk
    }

    add_opt() {
      cp -f $ZIPALIGN_OUTFILE/FaceLock.apk $SYSTEM_APP/FaceLock/FaceLock.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleCalendarSyncAdapter.apk $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleContactsSyncAdapter.apk $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleExtShared.apk $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      cp -f $ZIPALIGN_OUTFILE/MarkupGoogle.apk $SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk
      cp -f $ZIPALIGN_OUTFILE/SoundPickerPrebuilt.apk $SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk
      cp -f $ZIPALIGN_OUTFILE/CarrierSetup.apk $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk
      cp -f $ZIPALIGN_OUTFILE/ConfigUpdater.apk $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      cp -f $ZIPALIGN_OUTFILE/GmsCoreSetupPrebuilt.apk $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleExtServices.apk $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleServicesFramework.apk $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      cp -f $ZIPALIGN_OUTFILE/Phonesky.apk $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      cp -f $ZIPALIGN_OUTFILE/PrebuiltGmsCorePi.apk $SYSTEM_PRIV_APP/PrebuiltGmsCorePi/PrebuiltGmsCorePi.apk
    }

    perm_opt() {
      chmod 0644 $SYSTEM_APP/FaceLock/FaceLock.apk
      chmod 0644 $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      chmod 0644 $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      chmod 0644 $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      chmod 0644 $SYSTEM_APP/MarkupGoogle/MarkupGoogle.apk
      chmod 0644 $SYSTEM_APP/SoundPickerPrebuilt/SoundPickerPrebuilt.apk
      chmod 0644 $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk
      chmod 0644 $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      chmod 0644 $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
      chmod 0644 $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      chmod 0644 $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      chmod 0644 $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      chmod 0644 $SYSTEM_PRIV_APP/PrebuiltGmsCorePi/PrebuiltGmsCorePi.apk
    }
    # end opt method

    # execute installation functions
    sdk_v28() {
      extract_app;
      set_sparse;
      selinux_context_s1;
      selinux_context_sp2;
      selinux_context_sf3;
      selinux_context_sl4;
      selinux_context_sl5;
      selinux_context_se6;
      apk_opt;
      pre_opt;
      add_opt;
      perm_opt;
      # Re-run selinux functions for optimized APKs
      selinux_context_s1;
      selinux_context_sp2;
      # end selinux functions
    }
    sdk_v28;
    # Print installed files to sdk log
    cat $LOG >> $sdk_v28;
  else
    echo "Target Android SDK Version : $android_sdk" >> $sdk_v28;
  fi;
}

# Set installation functions for Android SDK 27
sdk_v27_install() {
  if [ "$android_sdk" = "$supported_sdk_v27" ]; then
    # Set default packages
    ZIP="
      zip/core/priv_app_CarrierSetup.tar.xz
      zip/core/priv_app_ConfigUpdater.tar.xz
      zip/core/priv_app_GmsCoreSetupPrebuilt.tar.xz
      zip/core/priv_app_GoogleExtServices.tar.xz
      zip/core/priv_app_GoogleServicesFramework.tar.xz
      zip/core/priv_app_Phonesky.tar.xz
      zip/core/priv_app_PrebuiltGmsCorePix.tar.xz
      zip/sys/sys_app_FaceLock.tar.xz
      zip/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz
      zip/sys/sys_app_GoogleContactsSyncAdapter.tar.xz
      zip/sys/sys_app_GoogleExtShared.tar.xz
      zip/sys_Config_Permission.tar.xz
      zip/sys_Default_Permission.tar.xz
      zip/sys_Framework.tar.xz
      zip/sys_Lib.tar.xz
      zip/sys_Lib64.tar.xz
      zip/sys_Permissions.tar.xz
      zip/sys_Pref_Permission.tar.xz"

    # Unzip system files from installer
    unpack_zip;

    # Unpack system files
    extract_app() {
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack SYS-APP Files" >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_FaceLock.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys/sys_app_FaceLock.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.xz -C $TMP_SYS;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack PRIV-APP Files" >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_CarrierSetup.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_ConfigUpdater.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GmsCoreSetupPrebuilt.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GoogleExtServices.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_Phonesky.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_PrebuiltGmsCorePix.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/core/priv_app_CarrierSetup.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_ConfigUpdater.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GmsCoreSetupPrebuilt.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GoogleExtServices.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_Phonesky.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_PrebuiltGmsCorePix.tar.xz -C $TMP_PRIV;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack Framework Files" >> $LOG;
      tar tvf $ZIP_FILE/sys_Framework.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Framework.tar.xz -C $TMP_FRAMEWORK;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Lib" >> $LOG;
      tar tvf $ZIP_FILE/sys_Lib.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Lib.tar.xz -C $TMP_LIB;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Lib64" >> $LOG;
      tar tvf $ZIP_FILE/sys_Lib64.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Lib64.tar.xz -C $TMP_LIB64;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Files" >> $LOG;
      tar tvf $ZIP_FILE/sys_Config_Permission.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Default_Permission.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Permissions.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Pref_Permission.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Config_Permission.tar.xz -C $TMP_CONFIG;
      tar -xf $ZIP_FILE/sys_Default_Permission.tar.xz -C $TMP_DEFAULT_PERM;
      tar -xf $ZIP_FILE/sys_Permissions.tar.xz -C $TMP_G_PERM;
      tar -xf $ZIP_FILE/sys_Pref_Permission.tar.xz -C $TMP_G_PREF;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Installation Complete" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "Finish at $( date +"%m-%d-%Y %H:%M:%S" )" >> $LOG;
      echo "-----------------------------------" >> $LOG;
    }

    # Set selinux context
    selinux_context_s1() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/FaceLock";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/FaceLock/FaceLock.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk";
    }

    selinux_context_sp2() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/CarrierSetup";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCorePix";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky/Phonesky.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCorePix/PrebuiltGmsCorePix.apk";
    }

    selinux_context_sf3() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.maps.jar";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.media.effects.jar";
    }

    selinux_context_sl4() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB/libfilterpack_facedetect.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB/libfrsdk.so";
    }

    selinux_context_sl5() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libfacenet.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libfilterpack_facedetect.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libfrsdk.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libjni_latinimegoogle.so";
    }

    selinux_context_se6() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/default-permissions.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/opengapps-permissions.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.dialer.support.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.maps.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.media.effects.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/privapp-permissions-google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps/google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/dialer_experience.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_build.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_exclusives_enable.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM/etc/g.prop";
    }
    # end selinux method
    
    # Create FaceLock lib symlink
    bind_facelock_lib() {
      ln -sfnv $SYSTEM/lib64/libfacenet.so $SYSTEM/app/FaceLock/lib/arm64/libfacenet.so >> $LINKER;
      rm -rf $SYSTEM/app/FaceLock/lib/arm64/placeholder
    }

    # APK optimization using zipalign tool
    apk_opt() {
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/FaceLock/FaceLock.apk $ZIPALIGN_OUTFILE/FaceLock.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk $ZIPALIGN_OUTFILE/GoogleCalendarSyncAdapter.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk $ZIPALIGN_OUTFILE/GoogleContactsSyncAdapter.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk $ZIPALIGN_OUTFILE/GoogleExtShared.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk $ZIPALIGN_OUTFILE/CarrierSetup.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk $ZIPALIGN_OUTFILE/ConfigUpdater.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk $ZIPALIGN_OUTFILE/GmsCoreSetupPrebuilt.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk $ZIPALIGN_OUTFILE/GoogleExtServices.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk $ZIPALIGN_OUTFILE/GoogleServicesFramework.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk $ZIPALIGN_OUTFILE/Phonesky.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/PrebuiltGmsCorePix/PrebuiltGmsCorePix.apk $ZIPALIGN_OUTFILE/PrebuiltGmsCorePix.apk >> $ZIPALIGN_LOG;
    }

    pre_opt() {
      rm -rf $SYSTEM_APP/FaceLock/FaceLock.apk
      rm -rf $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      rm -rf $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      rm -rf $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      rm -rf $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk
      rm -rf $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      rm -rf $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
      rm -rf $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      rm -rf $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      rm -rf $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      rm -rf $SYSTEM_PRIV_APP/PrebuiltGmsCorePix/PrebuiltGmsCorePix.apk
    }

    add_opt() {
      cp -f $ZIPALIGN_OUTFILE/FaceLock.apk $SYSTEM_APP/FaceLock/FaceLock.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleCalendarSyncAdapter.apk $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleContactsSyncAdapter.apk $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleExtShared.apk $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      cp -f $ZIPALIGN_OUTFILE/CarrierSetup.apk $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk
      cp -f $ZIPALIGN_OUTFILE/ConfigUpdater.apk $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      cp -f $ZIPALIGN_OUTFILE/GmsCoreSetupPrebuilt.apk $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleExtServices.apk $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleServicesFramework.apk $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      cp -f $ZIPALIGN_OUTFILE/Phonesky.apk $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      cp -f $ZIPALIGN_OUTFILE/PrebuiltGmsCorePix.apk $SYSTEM_PRIV_APP/PrebuiltGmsCorePix/PrebuiltGmsCorePix.apk
    }

    perm_opt() {
      chmod 0644 $SYSTEM_APP/FaceLock/FaceLock.apk
      chmod 0644 $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      chmod 0644 $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      chmod 0644 $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      chmod 0644 $SYSTEM_PRIV_APP/CarrierSetup/CarrierSetup.apk
      chmod 0644 $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      chmod 0644 $SYSTEM_PRIV_APP/GmsCoreSetupPrebuilt/GmsCoreSetupPrebuilt.apk
      chmod 0644 $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      chmod 0644 $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      chmod 0644 $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      chmod 0644 $SYSTEM_PRIV_APP/PrebuiltGmsCorePix/PrebuiltGmsCorePix.apk
    }
    # end opt method

    # execute installation functions
    sdk_v27() {
      extract_app;
      set_sparse;
      selinux_context_s1;
      selinux_context_sp2;
      selinux_context_sf3;
      selinux_context_sl4;
      selinux_context_sl5;
      selinux_context_se6;
      bind_facelock_lib;
      apk_opt;
      pre_opt;
      add_opt;
      perm_opt;
      # Re-run selinux functions for optimized APKs
      selinux_context_s1;
      selinux_context_sp2;
      # end selinux functions
    }
    sdk_v27;
    # Print installed files to sdk log
    cat $LOG >> $sdk_v27;
  else
    echo "Target Android SDK Version : $android_sdk" >> $sdk_v27;
  fi;
}

# Set installation functions for Android SDK 25
sdk_v25_install() {
  if [ "$android_sdk" = "$supported_sdk_v25" ]; then
    # Set default packages
    ZIP="
      zip/core/priv_app_ConfigUpdater.tar.xz
      zip/core/priv_app_GoogleExtServices.tar.xz
      zip/core/priv_app_GoogleLoginService.tar.xz
      zip/core/priv_app_GoogleServicesFramework.tar.xz
      zip/core/priv_app_Phonesky.tar.xz
      zip/core/priv_app_PrebuiltGmsCore.tar.xz
      zip/sys/sys_app_FaceLock.tar.xz
      zip/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz
      zip/sys/sys_app_GoogleContactsSyncAdapter.tar.xz
      zip/sys/sys_app_GoogleExtShared.tar.xz
      zip/sys_Config_Permission.tar.xz
      zip/sys_Default_Permission.tar.xz
      zip/sys_Framework.tar.xz
      zip/sys_Lib.tar.xz
      zip/sys_Lib64.tar.xz
      zip/sys_Permissions.tar.xz
      zip/sys_Pref_Permission.tar.xz"

    # Unzip system files from installer
    unpack_zip;

    # Unpack system files
    extract_app() {
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack SYS-APP Files" >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_FaceLock.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys/sys_app_FaceLock.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleCalendarSyncAdapter.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleContactsSyncAdapter.tar.xz -C $TMP_SYS;
      tar -xf $ZIP_FILE/sys/sys_app_GoogleExtShared.tar.xz -C $TMP_SYS;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack PRIV-APP Files" >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_ConfigUpdater.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GoogleExtServices.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GoogleLoginService.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_Phonesky.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/core/priv_app_PrebuiltGmsCore.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/core/priv_app_ConfigUpdater.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GoogleExtServices.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GoogleLoginService.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_GoogleServicesFramework.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_Phonesky.tar.xz -C $TMP_PRIV;
      tar -xf $ZIP_FILE/core/priv_app_PrebuiltGmsCore.tar.xz -C $TMP_PRIV;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack Framework Files" >> $LOG;
      tar tvf $ZIP_FILE/sys_Framework.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Framework.tar.xz -C $TMP_FRAMEWORK;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Lib" >> $LOG;
      tar tvf $ZIP_FILE/sys_Lib.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Lib.tar.xz -C $TMP_LIB;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Lib64" >> $LOG;
      tar tvf $ZIP_FILE/sys_Lib64.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Lib64.tar.xz -C $TMP_LIB64;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Unpack System Files" >> $LOG;
      tar tvf $ZIP_FILE/sys_Config_Permission.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Default_Permission.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Permissions.tar.xz >> $LOG;
      tar tvf $ZIP_FILE/sys_Pref_Permission.tar.xz >> $LOG;
      tar -xf $ZIP_FILE/sys_Config_Permission.tar.xz -C $TMP_CONFIG;
      tar -xf $ZIP_FILE/sys_Default_Permission.tar.xz -C $TMP_DEFAULT_PERM;
      tar -xf $ZIP_FILE/sys_Permissions.tar.xz -C $TMP_G_PERM;
      tar -xf $ZIP_FILE/sys_Pref_Permission.tar.xz -C $TMP_G_PREF;
      echo "- Done" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "- Installation Complete" >> $LOG;
      echo "-----------------------------------" >> $LOG;
      echo "Finish at $( date +"%m-%d-%Y %H:%M:%S" )" >> $LOG;
      echo "-----------------------------------" >> $LOG;
    }

    # Set selinux context
    selinux_context_s1() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/FaceLock";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/FaceLock/FaceLock.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk";
    }

    selinux_context_sp2() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleLoginService";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCore";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleLoginService/GoogleLoginService.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/Phonesky/Phonesky.apk";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk";
    }

    selinux_context_sf3() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.dialer.support.jar";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.maps.jar";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_FRAMEWORK/com.google.android.media.effects.jar";
    }

    selinux_context_sl4() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB/libfilterpack_facedetect.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB/libfrsdk.so";
    }

    selinux_context_sl5() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libfacenet.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libfilterpack_facedetect.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libfrsdk.so";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_LIB64/libjni_latinimegoogle.so";
    }

    selinux_context_se6() {
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/default-permissions.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_DEFAULT/default-permissions/opengapps-permissions.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.dialer.support.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.maps.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PERM/com.google.android.media.effects.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_PREF/preferred-apps/google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/dialer_experience.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_build.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM_ETC_CONFIG/google_exclusives_enable.xml";
      chcon -h u:object_r:system_file:s0 "$SYSTEM/etc/g.prop";
    }
    # end selinux method
    
    # Create FaceLock lib symlink
    bind_facelock_lib() {
      ln -sfnv $SYSTEM/lib64/libfacenet.so $SYSTEM/app/FaceLock/lib/arm64/libfacenet.so >> $LINKER;
      rm -rf $SYSTEM/app/FaceLock/lib/arm64/placeholder
    }

    # APK optimization using zipalign tool
    apk_opt() {
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/FaceLock/FaceLock.apk $ZIPALIGN_OUTFILE/FaceLock.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk $ZIPALIGN_OUTFILE/GoogleCalendarSyncAdapter.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk $ZIPALIGN_OUTFILE/GoogleContactsSyncAdapter.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk $ZIPALIGN_OUTFILE/GoogleExtShared.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk $ZIPALIGN_OUTFILE/ConfigUpdater.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk $ZIPALIGN_OUTFILE/GoogleExtServices.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleLoginService/GoogleLoginService.apk $ZIPALIGN_OUTFILE/GoogleLoginService.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk $ZIPALIGN_OUTFILE/GoogleServicesFramework.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk $ZIPALIGN_OUTFILE/Phonesky.apk >> $ZIPALIGN_LOG;
      $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk $ZIPALIGN_OUTFILE/PrebuiltGmsCore.apk >> $ZIPALIGN_LOG;
    }

    pre_opt() {
      rm -rf $SYSTEM_APP/FaceLock/FaceLock.apk
      rm -rf $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      rm -rf $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      rm -rf $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      rm -rf $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      rm -rf $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      rm -rf $SYSTEM_PRIV_APP/GoogleLoginService/GoogleLoginService.apk
      rm -rf $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      rm -rf $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      rm -rf $SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk
    }

    add_opt() {
      cp -f $ZIPALIGN_OUTFILE/FaceLock.apk $SYSTEM_APP/FaceLock/FaceLock.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleCalendarSyncAdapter.apk $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleContactsSyncAdapter.apk $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleExtShared.apk $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      cp -f $ZIPALIGN_OUTFILE/ConfigUpdater.apk $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleExtServices.apk $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleLoginService.apk $SYSTEM_PRIV_APP/GoogleLoginService/GoogleLoginService.apk
      cp -f $ZIPALIGN_OUTFILE/GoogleServicesFramework.apk $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      cp -f $ZIPALIGN_OUTFILE/Phonesky.apk $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      cp -f $ZIPALIGN_OUTFILE/PrebuiltGmsCore.apk $SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk
    }

    perm_opt() {
      chmod 0644 $SYSTEM_APP/FaceLock/FaceLock.apk
      chmod 0644 $SYSTEM_APP/GoogleCalendarSyncAdapter/GoogleCalendarSyncAdapter.apk
      chmod 0644 $SYSTEM_APP/GoogleContactsSyncAdapter/GoogleContactsSyncAdapter.apk
      chmod 0644 $SYSTEM_APP/GoogleExtShared/GoogleExtShared.apk
      chmod 0644 $SYSTEM_PRIV_APP/ConfigUpdater/ConfigUpdater.apk
      chmod 0644 $SYSTEM_PRIV_APP/GoogleExtServices/GoogleExtServices.apk
      chmod 0644 $SYSTEM_PRIV_APP/GoogleLoginService/GoogleLoginService.apk
      chmod 0644 $SYSTEM_PRIV_APP/GoogleServicesFramework/GoogleServicesFramework.apk
      chmod 0644 $SYSTEM_PRIV_APP/Phonesky/Phonesky.apk
      chmod 0644 $SYSTEM_PRIV_APP/PrebuiltGmsCore/PrebuiltGmsCore.apk
    }
    # end opt method

    # execute installation functions
    sdk_v25() {
      extract_app;
      set_sparse;
      selinux_context_s1;
      selinux_context_sp2;
      selinux_context_sf3;
      selinux_context_sl4;
      selinux_context_sl5;
      selinux_context_se6;
      bind_facelock_lib;
      apk_opt;
      pre_opt;
      add_opt;
      perm_opt;
      # Re-run selinux functions for optimized APKs
      selinux_context_s1;
      selinux_context_sp2;
      # end selinux functions
    }
    sdk_v25;
    # Print installed files to sdk log
    cat $LOG >> $sdk_v25;
  else
    echo "Target Android SDK Version : $android_sdk" >> $sdk_v25;
  fi;
}

# Set config dependent packages
ZIP_INITIAL="
  zip/core/priv_app_GoogleBackupTransport.tar.xz
  zip/core/priv_app_GoogleRestore.tar.xz
  zip/core/priv_app_SetupWizard.tar.xz"

# Unpack system files using config property
unpack_zip_initial() {
  for f in $ZIP_INITIAL; do
    unzip -o "$ZIPFILE" "$f" -d "$TMP";
  done
}

# Check whether config file present in device or not
get_config() {
  if [ -f /sdcard/bitgapps-config.prop ]; then
    build_config=true
  else
    build_config=false
  fi;
}

# Unpack config dependent packages
config_install() {
  if [ "$build_config" = "true" ]; then
    if [ "$supported_config" = "$supported_target" ]; then
      unpack_zip_initial;

      # Remove SetupWizard components
      pre_installed_initial() {
        if [ "$android_sdk" -gt "28" ]; then
          rm -rf $SYSTEM/product/app/ManagedProvisioning
          rm -rf $SYSTEM/product/app/Provision
          rm -rf $SYSTEM/product/priv-app/ManagedProvisioning
          rm -rf $SYSTEM/product/priv-app/Provision
        fi;
        rm -rf $SYSTEM_APP/ManagedProvisioning
        rm -rf $SYSTEM_APP/Provision
        rm -rf $SYSTEM_PRIV_APP/GoogleBackupTransport
        rm -rf $SYSTEM_PRIV_APP/GoogleRestore
        rm -rf $SYSTEM_PRIV_APP/ManagedProvisioning
        rm -rf $SYSTEM_PRIV_APP/Provision
        rm -rf $SYSTEM_PRIV_APP/SetupWizard
      }

      # Unpack SetupWizard components
      extract_app_initial() {
        tar tvf $ZIP_FILE/core/priv_app_GoogleBackupTransport.tar.xz >> $config_log;
        if [ "$android_sdk" -gt "25" ]; then # Unsupported component for SDK 25
          tar tvf $ZIP_FILE/core/priv_app_GoogleRestore.tar.xz >> $config_log;
        fi;
        tar tvf $ZIP_FILE/core/priv_app_SetupWizard.tar.xz >> $config_log;
        tar -xf $ZIP_FILE/core/priv_app_GoogleBackupTransport.tar.xz -C $TMP_PRIV_SETUP;
        if [ "$android_sdk" -gt "25" ]; then # Unsupported component for SDK 25
          tar -xf $ZIP_FILE/core/priv_app_GoogleRestore.tar.xz -C $TMP_PRIV_SETUP;
        fi;
        tar -xf $ZIP_FILE/core/priv_app_SetupWizard.tar.xz -C $TMP_PRIV_SETUP;
        set_sparse_excl;
      }

      # Selinux context for SetupWizard components
      selinux_context_sp2_initial() {
        chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleBackupTransport";
        if [ "$android_sdk" -gt "25" ]; then # Unsupported component for SDK 25
          chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleRestore";
        fi;
        chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/SetupWizard";
        chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleBackupTransport/GoogleBackupTransport.apk";
        if [ "$android_sdk" -gt "25" ]; then # Unsupported component for SDK 25
          chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/GoogleRestore/GoogleRestore.apk";
        fi;
        chcon -h u:object_r:system_file:s0 "$SYSTEM_PRIV_APP/SetupWizard/SetupWizard.apk";
      }

      # SetupWizard components optimization using zipalign tool
      apk_opt_initial() {
        $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleBackupTransport/GoogleBackupTransport.apk $ZIPALIGN_OUTFILE/GoogleBackupTransport.apk >> $ZIPALIGN_LOG;
        if [ "$android_sdk" -gt "25" ]; then # Unsupported component for SDK 25
          $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/GoogleRestore/GoogleRestore.apk $ZIPALIGN_OUTFILE/GoogleRestore.apk >> $ZIPALIGN_LOG;
        fi;
        $ZIPALIGN_TOOL -p -v 4 $SYSTEM_PRIV_APP/SetupWizard/SetupWizard.apk $ZIPALIGN_OUTFILE/SetupWizard.apk >> $ZIPALIGN_LOG;
      }

      pre_opt_initial() {
        rm -rf $SYSTEM_PRIV_APP/GoogleBackupTransport/GoogleBackupTransport.apk
        if [ "$android_sdk" -gt "25" ]; then # Unsupported component for SDK 25
          rm -rf $SYSTEM_PRIV_APP/GoogleRestore/GoogleRestore.apk
        fi;
        rm -rf $SYSTEM_PRIV_APP/SetupWizard/SetupWizard.apk
      }

      add_opt_initial() {
        cp -f $ZIPALIGN_OUTFILE/GoogleBackupTransport.apk $SYSTEM_PRIV_APP/GoogleBackupTransport/GoogleBackupTransport.apk
        if [ "$android_sdk" -gt "25" ]; then # Unsupported component for SDK 25
          cp -f $ZIPALIGN_OUTFILE/GoogleRestore.apk $SYSTEM_PRIV_APP/GoogleRestore/GoogleRestore.apk
        fi;
        cp -f $ZIPALIGN_OUTFILE/SetupWizard.apk $SYSTEM_PRIV_APP/SetupWizard/SetupWizard.apk
      }

      perm_opt_initial() {
        chmod 0644 $SYSTEM_PRIV_APP/GoogleBackupTransport/GoogleBackupTransport.apk
        if [ "$android_sdk" -gt "25" ]; then # Unsupported component for SDK 25
          chmod 0644 $SYSTEM_PRIV_APP/GoogleRestore/GoogleRestore.apk
        fi;
        chmod 0644 $SYSTEM_PRIV_APP/SetupWizard/SetupWizard.apk
      }

      # end opt initial method

      # Initiate SetupWizard components installation
      on_config_install() {
        pre_installed_initial;
        extract_app_initial;
        selinux_context_sp2_initial;
        apk_opt_initial;
        pre_opt_initial;
        add_opt_initial;
        perm_opt_initial;
        # Re-run selinux function for optimized APKs
        selinux_context_sp2_initial;
        # end selinux function
      }
      on_config_install;
    else
      echo "ERROR: Config property set to 'false'" >> $CONFIG;
    fi;
  else
    echo "ERROR: Config file not found" >> $CONFIG;
  fi;
}

# Enable Google Assistant
set_assistant() {
  insert_line $SYSTEM/build.prop "ro.opa.eligible_device=true" after 'net.bt.name=Android' 'ro.opa.eligible_device=true';
}

# Remove Privileged App Whitelist property with flag enforce
purge_whitelist_permission() {
  if [ -n "$(cat $SYSTEM/build.prop | grep control_privapp_permissions)" ]; then
    grep -v "$PROPFLAG" $SYSTEM/build.prop > /tmp/build.prop
    rm -rf $SYSTEM/build.prop
    cp -f /tmp/build.prop $SYSTEM/build.prop
    chmod 0644 $SYSTEM/build.prop
    rm -rf /tmp/build.prop
  else
    echo "ERROR: Unable to find Whitelist property" >> $whitelist;
  fi;
  if [ -f /system_root/system/etc/prop.default ]; then
    if [ -n "$(cat /system_root/system/etc/prop.default | grep control_privapp_permissions)" ]; then
      echo "system_root: prop.default present in device" >> $whitelist
      grep -v "$PROPFLAG" /system_root/system/etc/prop.default > /tmp/prop.default
      rm -rf /system_root/system/etc/prop.default
      rm -rf /system_root/default.prop
      cp -f /tmp/prop.default /system_root/system/etc/prop.default
      chmod 0644 /system_root/system/etc/prop.default
      ln -sfnv /system_root/system/etc/prop.default /system_root/default.prop
      rm -rf /tmp/prop.default
    else
      echo "ERROR: Unable to find Whitelist property" >> $whitelist;
    fi;
  else
    echo "ERROR: unable to find prop.default" >> $whitelist;
  fi;
  if [ "$device_vendorpartition" = "true" ]; then
    if [ -n "$(cat $VENDOR/build.prop | grep control_privapp_permissions)" ]; then
      grep -v "$PROPFLAG" $VENDOR/build.prop > /tmp/build.prop
      rm -rf $VENDOR/build.prop
      cp -f /tmp/build.prop $VENDOR/build.prop
      chmod 0644 $VENDOR/build.prop
      rm -rf /tmp/build.prop
    else
      echo "ERROR: Unable to find Whitelist property" >> $whitelist;
    fi;
  else
    echo "ERROR: No vendor partition present" >> $whitelist;
  fi;
}

# Add Whitelist property with flag disable in system
set_whitelist_permission() {
  insert_line $SYSTEM/build.prop "ro.control_privapp_permissions=disable" after 'net.bt.name=Android' 'ro.control_privapp_permissions=disable';
}

# Apply safetynet patch
cts_patch_system() {
  # Build fingerprint
  if [ -n "$(cat $SYSTEM/build.prop | grep ro.build.fingerprint)" ]; then
    grep -v "$CTS_DEFAULT_SYSTEM_BUILD_FINGERPRINT" $SYSTEM/build.prop > /tmp/build.prop
    rm -rf $SYSTEM/build.prop
    cp -f /tmp/build.prop $SYSTEM/build.prop
    chmod 0644 $SYSTEM/build.prop
    rm -rf /tmp/build.prop
    insert_line $SYSTEM/build.prop "$CTS_SYSTEM_BUILD_FINGERPRINT" after 'ro.build.description=' "$CTS_SYSTEM_BUILD_FINGERPRINT";
  else
    insert_line $SYSTEM/build.prop "$CTS_SYSTEM_BUILD_FINGERPRINT" after 'ro.build.description=' "$CTS_SYSTEM_BUILD_FINGERPRINT";
  fi;
  # Build security patch
  if [ -n "$(cat $SYSTEM/build.prop | grep ro.build.version.security_patch)" ]; then
    grep -v "$CTS_DEFAULT_SYSTEM_BUILD_SEC_PATCH" $SYSTEM/build.prop > /tmp/build.prop
    rm -rf $SYSTEM/build.prop
    cp -f /tmp/build.prop $SYSTEM/build.prop
    chmod 0644 $SYSTEM/build.prop
    rm -rf /tmp/build.prop
    insert_line $SYSTEM/build.prop "$CTS_SYSTEM_BUILD_SEC_PATCH" after 'ro.build.version.release=' "$CTS_SYSTEM_BUILD_SEC_PATCH";
  else
    insert_line $SYSTEM/build.prop "$CTS_SYSTEM_BUILD_SEC_PATCH" after 'ro.build.version.release=' "$CTS_SYSTEM_BUILD_SEC_PATCH";
  fi;
}

# Apply safetynet patch
cts_patch_vendor() {
  if [ "$device_vendorpartition" = "true" ]; then
    # Build fingerprint
    if [ -n "$(cat $VENDOR/build.prop | grep ro.vendor.build.fingerprint)" ]; then
      grep -v "$CTS_DEFAULT_VENDOR_BUILD_FINGERPRINT" $VENDOR/build.prop > /tmp/build.prop
      rm -rf $VENDOR/build.prop
      cp -f /tmp/build.prop $VENDOR/build.prop
      chmod 0644 $VENDOR/build.prop
      rm -rf /tmp/build.prop
      insert_line $VENDOR/build.prop "$CTS_VENDOR_BUILD_FINGERPRINT" after 'ro.vendor.build.date.utc=' "$CTS_VENDOR_BUILD_FINGERPRINT";
    else
      insert_line $VENDOR/build.prop "$CTS_VENDOR_BUILD_FINGERPRINT" after 'ro.vendor.build.date.utc=' "$CTS_VENDOR_BUILD_FINGERPRINT";
    fi;
    # Build bootimage
    if [ -n "$(cat $VENDOR/build.prop | grep ro.bootimage.build.fingerprint)" ]; then
      grep -v "$CTS_DEFAULT_VENDOR_BUILD_BOOTIMAGE" $VENDOR/build.prop > /tmp/build.prop
      rm -rf $VENDOR/build.prop
      cp -f /tmp/build.prop $VENDOR/build.prop
      chmod 0644 $VENDOR/build.prop
      rm -rf /tmp/build.prop
      insert_line $VENDOR/build.prop "$CTS_VENDOR_BUILD_BOOTIMAGE" after 'ro.bootimage.build.date.utc=' "$CTS_VENDOR_BUILD_BOOTIMAGE";
    else
      insert_line $VENDOR/build.prop "$CTS_VENDOR_BUILD_BOOTIMAGE" after 'ro.vendor.build.fingerprint=' "$CTS_VENDOR_BUILD_BOOTIMAGE";
    fi;
  else
    echo "ERROR: No vendor partition present" >> $PARTITION;
  fi;
}

# Disable Privileged permission patch function for CAF based ROMs
whitelist_patch() {
  if [ -n "$(cat $SYSTEM/build.prop | grep ro.reloaded.device)" ]; then
    echo "Privileged Permission Patch disabled for CAF based ROM" >> $whitelist;
    echo "CAF ROM Device : $caf_product" >> $whitelist;
  else
    purge_whitelist_permission;
    set_whitelist_permission;
  fi;
}

# Disable CTS patch function for Samsung devices and CAF based ROMs
cts_patch() {
  if [ "$android_product" = "$supported_product" ] || [ -n "$(cat $SYSTEM/build.prop | grep ro.reloaded.device)" ]; then
    if [ "$android_product" = "$supported_product" ]; then
      echo "CTS Patch disabled for Product : $android_product" >> $CTS_PATCH;
    fi;
    if [ -n "$(cat $SYSTEM/build.prop | grep ro.reloaded.device)" ]; then
      echo "CTS Patch disabled for CAF based ROM" >> $CTS_PATCH;
      echo "CAF ROM Device : $caf_product" >> $CTS_PATCH;
    fi;
  else
    cts_patch_system;
    cts_patch_vendor;
  fi;
}

# API fixes
sdk_fix() {
  if [ "$android_sdk" -ge "26" ]; then # Android 8.0+ uses 0600 for its permission on build.prop
    chmod 0600 "$SYSTEM/build.prop"
    if [ "$device_vendorpartition" = "true" ]; then
      chmod 0600 "$VENDOR/build.prop"
    fi;
  fi;
}

ui_print "Mount Partitions";

ui_print " ";

# These set of functions should be executed before any other install function
function pre_install() {
  clean_logs;
  logd;
  on_sdk;
  on_platform;
  early_mount;
  set_mount;
  mount_part;
  vendor_fallback;
  remount_part;
  system_layout;
  profile;
  on_AB;
  mount_stat;
  on_version_check;
  check_sdk;
  check_version;
  on_platform_check;
  check_platform;
  patch_init_Vendor_PM;
  patch_init_Vendor_SQLITE;
}
pre_install;

# Get the available space left on the device
size=`df -k $SYSTEM_MOUNT | tail -n 1 | tr -s ' ' | cut -d' ' -f4`
CAPACITY="200000"

# Check if the available space is greater than 200MB (200000KB)
ui_print "Checking System Space";
if [[ "$size" -gt "$CAPACITY" ]]; then
  ui_print "$size";
  ui_print " ";
else
  ui_print " ";
  on_abort "No space left in device. Aborting...";
  ui_print " ";
fi;

ui_print "Installing";

# Do not merge 'pre_install' functions here
# Begin installation
function post_install() {
  system_pathmap;
  recovery_actions;
  mk_component;
  pre_installed_v29;
  pre_installed_v28;
  pre_installed_v27;
  pre_installed_v25;
  sdk_v29_install;
  sdk_v28_install;
  sdk_v27_install;
  sdk_v25_install;
  get_config;
  config_install;
  set_assistant;
  on_caf_check;
  whitelist_patch;
  on_product_check;
  cts_patch;
  sdk_fix;
  on_installed;
  recovery_cleanup;
}
post_install; # end installation

# Do not parse this function
print_build_info;

# end method