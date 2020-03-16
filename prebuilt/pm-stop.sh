#!/system/bin/sh
#
##############################################################
# File name       : pm-stop.sh
#
# Description     : Stop init service pm_start
#
# Build Date      : Friday December 20 16:26:13 IST 2019
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
# This script is the part of android init script and executed
# after "pm_start" service. Invoke sleep function before stopping
# "pm_start" service so that the service do not gets immediately
# killed by "pm_stop" service.
##############################################################

# Sleep for 120 seconds
sleep 120;

# Stop service, as it does not have 'oneshot' init function
stop pm_start

# end method