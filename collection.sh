#!/usr/bin/env bash

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Collect all logs
#   Author: Christian Trautman <ctrautma@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2017 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# create time date stamp for archive and get hostname
time_stamp=$(date +%Y-%m-%d-%T)
myhost=`echo $hostname`


# install sos if needed
if ! [ `command -v lrzip ` ]
then
    yum install -y sos || exit 1 "!!!Could not install sos!!!"
fi

# run sos and add it to archive
sosreport --batch &> soscollect.txt
sosreport_log=`cat soscollect.txt | grep "tar.xz"`
tar czf $myhost_$time_stamp.tar.gz $sosreport_log

if test -f root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
then
    source /root/RHEL_NIC_QUAL_LOGS/vsperf_logs_folder.txt
    tar czf $myhost_$time_stamp.tar.gz $NIC_LOG_FOLDER
fi

if test -f /root/RHEL_NIC_QUAL_LOGS/kernel_functional_logs.txt
then
    source /root/RHEL_NIC_QUAL_LOGS/kernel_functional_logs.txt
    tar czf $myhost_$time_stamp.tar.gz $NIC_LOG_FOLDER_KERNEL
fi

echo "Please provide file $myhost_$time_stamp.tar.gz to Redhat Certification Team"
