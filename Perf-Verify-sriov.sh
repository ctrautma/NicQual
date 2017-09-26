#!/usr/bin/env bash

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Run VSPerf tests
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

#set -o allexport
#source Perf-Verify.sh
#set +o allexport
. ./Perf-Verify.sh --source-only

echo "*** SR-IOV MUST be enabled already for this test to work!!!! ***"

generate_sriov_conf() {

    NIC1_VF_PCI_ADDR=`ethtool -i $NIC1_VF | grep -Eo '[0-9]+:[0-9]+:[0-9]+\.[0-9]+'`
    NIC2_VF_PCI_ADDR=`ethtool -i $NIC2_VF | grep -Eo '[0-9]+:[0-9]+:[0-9]+\.[0-9]+'`
    NIC1_VF_MAC=`cat /sys/class/net/$NIC1_VF/address`
    NIC2_VF_MAC=`cat /sys/class/net/$NIC2_VF/address`


cat <<EOT >>/root/vswitchperf/sriov.conf

TRAFFIC = {
    'traffic_type' : 'rfc2544_throughput',
    'frame_rate' : 100,
    'bidir' : 'True',  # will be passed as string in title format to tgen
    'multistream' : 1024,
    'stream_type' : 'L3',
    'pre_installed_flows' : 'No',           # used by vswitch implementation
    'flow_type' : 'port',                   # used by vswitch implementation

    'l2': {
        'framesize': 64,
        'srcmac': '$NIC1_VF_MAC',
        'dstmac': '$NIC2_VF_MAC',
    },
    'l3': {
        'enabled': True,
        'proto': 'udp',
        'srcip': '1.1.1.1',
        'dstip': '90.90.90.90',
    },
    'l4': {
        'enabled': True,
        'srcport': 3000,
        'dstport': 3001,
    },
    'vlan': {
        'enabled': False,
        'id': 0,
        'priority': 0,
        'cfi': 0,
    },
}
WHITELIST_NICS = ['$NIC1_VF_PCI_ADDR', '$NIC2_VF_PCI_ADDR']

PIDSTAT_MONITOR = ['ovs-vswitchd', 'ovsdb-server', 'qemu-system-x86_64', 'vpp', 'testpmd', 'qemu-kvm']
TRAFFICGEN_TREX_PROMISCUOUS=True

GUEST_TESTPMD_PARAMS = ['-l 0,1,2 -n 4 --socket-mem 512 -- '
                        '--burst=64 -i --txqflags=0xf00 '
                        '--disable-hw-vlan --nb-cores=2, --txq=1 --rxq=1 --rxd=2048 --txd=2048']

EOT

}

run_sriov_tests() {
    echo ""
    echo "************************************************"
    echo "*** Running 64/1500 Bytes SR-IOV VSPerf TEST ***"
    echo "************************************************"
    echo ""

cd /root/vswitchperf
scl enable python33 - << \EOF
source /root/vsperfenv/bin/activate
python ./vsperf pvp_tput --conf-file=/root/vswitchperf/sriov.conf --vswitch=none --vnf=QemuPciPassthrough &> vsperf_pvp_sriov.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid

    if [[ `grep "Overall test report written to" vsperf_pvp_sriov.log` ]]
    then

        echo ""
        echo "########################################################"

        mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" vsperf_pvp_sriov.log | awk '{print $11}' )
        if [ "${array[0]%%.*}" -gt 18000000 ]
        then
            echo "# 64   Byte SR-IOV Passthrough PVP test result: ${array[0]} #"
        else
            echo "# 64 Bytes SR-IOV Passthrough PVP failed to reach required 18 Mpps got ${array[0]} #"
        fi

        if [ "${array[1]%%.*}" -gt 1600000 ]
        then
            echo "# 1500 Byte SR-IOV Passthrough PVP test result: ${array[1]} #"
        else
            echo "# 1500 Bytes SR-IOV Passthrough PVP failed to reach required 1.6 Mpps got ${array[0]} #"
        fi

        echo "########################################################"
        echo ""

        if [ "${array[0]%%.*}" -lt 400000 ] || [ "${array[1]%%.*}" -lt 300000 ]
        then
            fail "64/1500 SR-IOV Passthrough PVP" "Failed to achieve required pps on tests"
        fi
    else
        echo "!!! VSPERF Test Failed !!!!"
        fail "Error on VSPerf test" "VSPerf test failed. Please check log at /root/vswitchperf/vsperf_pvp_sriov.log"
    fi

}


sriov_check() {

    echo "*** Checking Config File for SR-IOV info***"
    sleep 1

    if test -f ./Perf-Verify.conf
    then
        set -o allexport
        source Perf-Verify.conf
        set +o allexport
        if [[ -z $NIC1_VF ]] || [[ -z $NIC2_VF ]]
        then
            fail "NIC_VF Param" "NIC_VF Params not set in Perf-Verify.conf file"
        fi
    else
        fail "Config File" "Cannot locate Perf-Verify.conf"
    fi

    echo "*** Checking for VFs ***"
    if [[ ! `ip a | grep $NIC1_VF` ]] ||  [[ ! `ip a | grep $NIC2_VF` ]]
    then
        fail "NIC_VF Check" "NIC_VF $NIC1_VF or NIC_VF $NIC2_VF cannot be seen by kernel"
    fi

}

OS_checks
hugepage_checks
sriov_check
conf_checks
config_file_checks
rpm_check
network_connection_check
ovs_running_check

git_clone_vsperf
vsperf_make
customize_VSPerf_code

download_VNF_image
download_conf_files

generate_sriov_conf
run_sriov_tests
