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

# Detect OS name and version from systemd based os-release file
. /etc/os-release

OS_checks() {

    echo "*** Running System Checks ***"
    sleep 1

    # Verify user is root
    echo "*** Running User Check ***"
    sleep 1

    if [ $USER != "root" ]
    then
        fail "User Check" "Must be logged in as root"
    fi

    # Verify OS is Rhel
    echo "*** Running OS Check ***"
    sleep 1

    if [ $ID != "rhel" ]
    then
        fail "OS Check" "OS Much be RHEL"
    fi

}

conf_checks() {

    # get the cat proc cmdline for parsing the next few checks
    PROCESS_CMD_LINE=`cat /proc/cmdline`

    # Verify iommu is enabled for vfio-pci
    echo "*** Checking for iommu enablement ***"
    sleep 1

    if ! [[ `echo $PROCESS_CMD_LINE | grep "intel_iommu=on"` ]]
    then
        fail "Iommu Enablement" "Please enable IOMMU mode in your grub config"
    fi

    echo "*** Checking Tunings ***"
    sleep 1

    if ! [[ `tuned-adm active | grep cpu-partitioning` ]]
    then
        fail "Tuned-adm" "cpu-partitioning profile must be active"
    fi

    if ! [[ `echo $PROCESS_CMD_LINE | grep "nohz_full=[0-9]"` ]]
    then
        fail "Tuned Config" "Must set cores to isolate in tuned-adm profile"
    fi

}

hugepage_checks() {

    echo "*** Checking Hugepage Config ***"
    sleep 1

    if ! [[ `cat /proc/meminfo | awk /Hugepagesize/ | awk /1048576/` ]]
    then
        fail "Hugepage Check" "Please enable 1G Hugepages"
    fi

}

config_file_checks() {

    echo "*** Checking Config File ***"
    sleep 1

    if test -f ./Perf-Verify.conf
    then
        set -o allexport
        source Perf-Verify.conf
        set +o allexport
        if [[ -z $NIC1 ]] || [[ -z $NIC2 ]]
        then
            fail "NIC Param" "NIC Params not set in Perf-Verify.conf file"
        fi
        if [ -z $PMD2MASK ] || [ -z $PMD4MASK ]
        then
            fail "PMD Mask PARAM" "PMD2MASK Param and/or PMD4MASK not set in Perf-Verify.conf file"
        fi
        if [ -z $VCPU1 ] || [ -z $VCPU2 ] || [ -z $VCPU3 ]
        then
            fail "VCPU Params" "Guest VCPU Param not set in Perf-Verify.conf file"
        fi
    else
        fail "Config File" "Cannot locate Perf-Verify.conf"
    fi

}

nic_card_check() {

    echo "*** Checking for NIC cards ***"
    if [[ ! `ip a | grep $NIC1` ]] ||  [[ ! `ip a | grep $NIC2` ]]
    then
        fail "NIC Check" "NIC $NIC1 or NIC $NIC2 cannot be seen by kernel"
    fi

}

rpm_check() {

    echo "*** Checking for installed RPMS ***"
    sleep 1

    if ! [[ `rpm -qa | grep ^openvswitch-[0-9]` ]]
    then
        fail "Openvswitch rpm" "Please install Openvswitch rpm"
    fi
    if ! [ `rpm -qa | grep dpdk-tools` ]
    then
        fail "DPDK Tools rpm" "Please install dpdk tools rpm"
    fi
    if ! [ `rpm -qa | grep dpdk-[0-9]` ]
    then
        fail "DPDK package rpm" "Please install dpdk package rpm"
    fi
    if ! [ `rpm -qa | grep qemu-kvm-rhev` ]
    then
        fail "QEMU-KVM-RHEV rpms" "Please install qemu-kvm-rhev rpm"
    fi

}

network_connection_check() {

     echo "*** Checking github connection ***"
     if ping -c 1 www.github.com &> /dev/null
     then
         echo "*** Connection to server succesful ***"
     else
         fail "Github connection fail" "!!! Cannot connect to www.github.com, please verify internet connection !!!"
     fi

}

ovs_running_check() {

     echo "*** Checking for running instance of Openvswitch ***"
     if [ `pgrep ovs-vswitchd` ] || [ `pgrep ovsdb-server` ]
     then
         fail "Openvswitch running" "It appears Openvswitch may be running, please stop all services and processes"
     fi

     cd ~

}

customize_VSPerf_code() {

    echo "*** Customizing VSPerf source code ***"

    # remove drive sharing
    sed -i "/                     '-drive',$/,+3 d" ~/vswitchperf/vnfs/qemu/qemu.py
    sed -i "/self._copy_fwd_tools_for_all_guests()/c\#self._copy_fwd_tools_for_all_guests()" ~/vswitchperf/testcases/testcase.py

    # add code to deal with custom image
    cat <<EOT >>vnfs/qemu/qemu.py
    def _configure_testpmd(self):
        """
        Configure VM to perform L2 forwarding between NICs by DPDK's testpmd
        """
        #self._configure_copy_sources('DPDK')
        self._configure_disable_firewall()

        # Guest images _should_ have 1024 hugepages by default,
        # but just in case:'''
        self.execute_and_wait('sysctl vm.nr_hugepages={}'.format(S.getValue('GUEST_HUGEPAGES_NR')[self._number]))

        # Mount hugepages
        self.execute_and_wait('mkdir -p /dev/hugepages')
        self.execute_and_wait(
            'mount -t hugetlbfs hugetlbfs /dev/hugepages')

        self.execute_and_wait('cat /proc/meminfo')
        self.execute_and_wait('rpm -ivh ~/dpdkrpms/1705/*.rpm ')
        self.execute_and_wait('cat /proc/cmdline')
        self.execute_and_wait('dpdk-devbind --status')

        # disable network interfaces, so DPDK can take care of them
        for nic in self._nics:
            self.execute_and_wait('ifdown ' + nic['device'])

        self.execute_and_wait('dpdk-bind --status')
        pci_list = ' '.join([nic['pci'] for nic in self._nics])
        self.execute_and_wait('dpdk-devbind -u ' + pci_list)
        self._bind_dpdk_driver(S.getValue(
            'GUEST_DPDK_BIND_DRIVER')[self._number], pci_list)
        self.execute_and_wait('dpdk-devbind --status')

        # get testpmd settings from CLI
        testpmd_params = S.getValue('GUEST_TESTPMD_PARAMS')[self._number]
        if S.getValue('VSWITCH_JUMBO_FRAMES_ENABLED'):
            testpmd_params += ' --max-pkt-len={}'.format(S.getValue(
                'VSWITCH_JUMBO_FRAMES_SIZE'))

        self.execute_and_wait('testpmd {}'.format(testpmd_params), 60, "Done")
        self.execute('set fwd ' + self._testpmd_fwd_mode, 1)
        self.execute_and_wait('start', 20, 'testpmd>')

    def _bind_dpdk_driver(self, driver, pci_slots):
        """
        Bind the virtual nics to the driver specific in the conf file
        :return: None
        """
        if driver == 'uio_pci_generic':
            if S.getValue('VNF') == 'QemuPciPassthrough':
                # unsupported config, bind to igb_uio instead and exit the
                # outer function after completion.
                self._logger.error('SR-IOV does not support uio_pci_generic. '
                                   'Igb_uio will be used instead.')
                self._bind_dpdk_driver('igb_uio_from_src', pci_slots)
                return
            self.execute_and_wait('modprobe uio_pci_generic')
            self.execute_and_wait('dpdk-devbind -b uio_pci_generic '+
                                  pci_slots)
        elif driver == 'vfio_no_iommu':
            self.execute_and_wait('modprobe -r vfio')
            self.execute_and_wait('modprobe -r vfio_iommu_type1')
            self.execute_and_wait('modprobe vfio enable_unsafe_noiommu_mode=Y')
            self.execute_and_wait('modprobe vfio-pci')
            self.execute_and_wait('dpdk-devbind -b vfio-pci ' +
                                  pci_slots)
        elif driver == 'igb_uio_from_src':
            # build and insert igb_uio and rebind interfaces to it
            self.execute_and_wait('make RTE_OUTPUT=$RTE_SDK/$RTE_TARGET -C '
                                  '$RTE_SDK/lib/librte_eal/linuxapp/igb_uio')
            self.execute_and_wait('modprobe uio')
            self.execute_and_wait('insmod %s/kmod/igb_uio.ko' %
                                  S.getValue('RTE_TARGET'))
            self.execute_and_wait('dpdk-devbind -b igb_uio ' + pci_slots)
        else:
            self._logger.error(
                'Unknown driver for binding specified, defaulting to igb_uio')
            self._bind_dpdk_driver('igb_uio_from_src', pci_slots)

EOT
if [ ! -d src/dpdk/dpdk/lib/librte_eal/common/include/ ]
then
    mkdir -p src/dpdk/dpdk/lib/librte_eal/common/include/

cat <<EOT >>src/dpdk/dpdk/lib/librte_eal/common/include/rte_version.h
 /*-
 *   BSD LICENSE
 *
 *   Copyright(c) 2010-2014 Intel Corporation. All rights reserved.
 *   All rights reserved.
 *
 *   Redistribution and use in source and binary forms, with or without
 *   modification, are permitted provided that the following conditions
 *   are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in
 *       the documentation and/or other materials provided with the
 *       distribution.
 *     * Neither the name of Intel Corporation nor the names of its
 *       contributors may be used to endorse or promote products derived
 *       from this software without specific prior written permission.
 *
 *   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *   LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *   THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * @file
 * Definitions of DPDK version numbers
 */

#ifndef _RTE_VERSION_H_
#define _RTE_VERSION_H_

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <string.h>
#include <rte_common.h>

/**
 * String that appears before the version number
 */
#define RTE_VER_PREFIX "DPDK"

/**
 * Major version/year number i.e. the yy in yy.mm.z
 */
#define RTE_VER_YEAR 16

/**
 * Minor version/month number i.e. the mm in yy.mm.z
 */
#define RTE_VER_MONTH 4

/**
 * Patch level number i.e. the z in yy.mm.z
 */
#define RTE_VER_MINOR 0

/**
 * Extra string to be appended to version number
 */
#define RTE_VER_SUFFIX ""

/**
 * Patch release number
 *   0-15 = release candidates
 *   16   = release
 */
#define RTE_VER_RELEASE 16

/**
 * Macro to compute a version number usable for comparisons
 */
#define RTE_VERSION_NUM(a,b,c,d) ((a) << 24 | (b) << 16 | (c) << 8 | (d))

/**
 * All version numbers in one to compare with RTE_VERSION_NUM()
 */
#define RTE_VERSION RTE_VERSION_NUM( \
			RTE_VER_YEAR, \
			RTE_VER_MONTH, \
			RTE_VER_MINOR, \
			RTE_VER_RELEASE)

/**
 * Function returning version string
 * @return
 *     string
 */
static inline const char *
rte_version(void)
{
	static char version[32];
	if (version[0] != 0)
		return version;
	if (strlen(RTE_VER_SUFFIX) == 0)
		snprintf(version, sizeof(version), "%s %d.%02d.%d",
			RTE_VER_PREFIX,
			RTE_VER_YEAR,
			RTE_VER_MONTH,
			RTE_VER_MINOR);
	else
		snprintf(version, sizeof(version), "%s %d.%02d.%d%s%d",
			RTE_VER_PREFIX,
			RTE_VER_YEAR,
			RTE_VER_MONTH,
			RTE_VER_MINOR,
			RTE_VER_SUFFIX,
			RTE_VER_RELEASE < 16 ?
				RTE_VER_RELEASE :
				RTE_VER_RELEASE - 16);
	return version;
}

#ifdef __cplusplus
}
#endif

#endif /* RTE_VERSION_H */
EOT

fi

}

download_conf_files() {

    echo "*** Creating VSPerf custom conf files ***"

    NIC1_PCI_ADDR=`ethtool -i $NIC1 | grep -Eo '[0-9]+:[0-9]+:[0-9]+\.[0-9]+'`
    NIC2_PCI_ADDR=`ethtool -i $NIC2 | grep -Eo '[0-9]+:[0-9]+:[0-9]+\.[0-9]+'`

    cat <<EOT >> ~/vswitchperf/conf/10_custom.conf

PATHS['qemu'] = {
    'type' : 'bin',
    'src': {
        'path': os.path.join(ROOT_DIR, 'src/qemu/qemu/'),
        'qemu-system': 'x86_64-softmmu/qemu-system-x86_64'
    },
    'bin': {
        'qemu-system': '/usr/libexec/qemu-kvm'
    }
}

PATHS['vswitch'] = {
    'none' : {      # used by SRIOV tests
        'type' : 'src',
        'src' : {},
    },
    'OvsDpdkVhost': {
        'type' : 'bin',
        'src': {
            'path': os.path.join(ROOT_DIR, 'src/ovs/ovs/'),
            'ovs-vswitchd': 'vswitchd/ovs-vswitchd',
            'ovsdb-server': 'ovsdb/ovsdb-server',
            'ovsdb-tool': 'ovsdb/ovsdb-tool',
            'ovsschema': 'vswitchd/vswitch.ovsschema',
            'ovs-vsctl': 'utilities/ovs-vsctl',
            'ovs-ofctl': 'utilities/ovs-ofctl',
            'ovs-dpctl': 'utilities/ovs-dpctl',
            'ovs-appctl': 'utilities/ovs-appctl',
        },
        'bin': {
            'ovs-vswitchd': 'ovs-vswitchd',
            'ovsdb-server': 'ovsdb-server',
            'ovsdb-tool': 'ovsdb-tool',
            'ovsschema': '/usr/share/openvswitch/vswitch.ovsschema',
            'ovs-vsctl': 'ovs-vsctl',
            'ovs-ofctl': 'ovs-ofctl',
            'ovs-dpctl': 'ovs-dpctl',
            'ovs-appctl': 'ovs-appctl',
        }
    },
    'ovs_var_tmp': '/usr/local/var/run/openvswitch/',
    'ovs_etc_tmp': '/usr/local/etc/openvswitch/',
    'VppDpdkVhost': {
        'type' : 'bin',
        'src': {
            'path': os.path.join(ROOT_DIR, 'src/vpp/vpp/build-root/build-vpp-native'),
            'vpp': 'vpp',
            'vppctl': 'vppctl',
        },
        'bin': {
            'vpp': 'vpp',
            'vppctl': 'vppctl',
        }
    },
}

PATHS['dpdk'] = {
        'type' : 'bin',
        'src': {
            'path': os.path.join(ROOT_DIR, 'src/dpdk/dpdk/'),
            # To use vfio set:
            # 'modules' : ['uio', 'vfio-pci'],
            'modules' : ['uio', os.path.join(RTE_TARGET, 'kmod/igb_uio.ko')],
            'bind-tool': 'tools/dpdk*bind.py',
            'testpmd': os.path.join(RTE_TARGET, 'app', 'testpmd'),
        },
        'bin': {
            'bind-tool': '/usr/share/dpdk/tools/dpdk-devbind.py',
            'modules' : ['uio', 'vfio-pci'],
            'testpmd' : 'testpmd'
        }
    }

PATHS['vswitch'].update({'OvsVanilla' : copy.deepcopy(PATHS['vswitch']['OvsDpdkVhost'])})
PATHS['vswitch']['ovs_var_tmp'] = '/var/run/openvswitch/'
PATHS['vswitch']['ovs_etc_tmp'] = '/etc/openvswitch/'
PATHS['vswitch']['OvsVanilla']['bin']['modules'] = [
        'libcrc32c', 'ip_tunnel', 'vxlan', 'gre', 'nf_nat', 'nf_nat_ipv6',
        'nf_nat_ipv4', 'nf_conntrack', 'nf_defrag_ipv4', 'nf_defrag_ipv6',
        'openvswitch']
PATHS['vswitch']['OvsVanilla']['type'] = 'bin'

GUEST_NIC_MERGE_BUFFERS_DISABLE = [True]

VSWITCH_JUMBO_FRAMES_ENABLED = False
VSWITCH_JUMBO_FRAMES_SIZE = 9000

VSWITCH_DPDK_MULTI_QUEUES = 0
GUEST_NIC_QUEUES = [0]

WHITELIST_NICS = ['$NIC1_PCI_ADDR', '$NIC2_PCI_ADDR']

DPDK_SOCKET_MEM = ['1024', '1024']

VSWITCH_PMD_CPU_MASK = '$PMD2MASK'

GUEST_SMP = ['3']

GUEST_CORE_BINDING = [('$VCPU1', '$VCPU2', '$VCPU3')]

GUEST_IMAGE = ['CentOS73.qcow2']

GUEST_BOOT_DRIVE_TYPE = ['ide']
GUEST_SHARED_DRIVE_TYPE = ['ide']

GUEST_DPDK_BIND_DRIVER = ['vfio_no_iommu']

GUEST_PASSWORD = ['redhat']

GUEST_NICS = [[{'device' : 'eth0', 'mac' : '#MAC(00:00:00:00:00:01,2)', 'pci' : '00:03.0', 'ip' : '#IP(192.168.1.2,4)/24'},
               {'device' : 'eth1', 'mac' : '#MAC(00:00:00:00:00:02,2)', 'pci' : '00:04.0', 'ip' : '#IP(192.168.1.3,4)/24'},
               {'device' : 'eth2', 'mac' : '#MAC(cc:00:00:00:00:01,2)', 'pci' : '00:06.0', 'ip' : '#IP(192.168.1.4,4)/24'},
               {'device' : 'eth3', 'mac' : '#MAC(cc:00:00:00:00:02,2)', 'pci' : '00:07.0', 'ip' : '#IP(192.168.1.5,4)/24'},
             ]]

GUEST_MEMORY = ['4096']

GUEST_HUGEPAGES_NR = ['1']

GUEST_TESTPMD_FWD_MODE = ['io']

GUEST_TESTPMD_PARAMS = ['-l 0,1,2 -n 4 --socket-mem 512 -- '
                        '--burst=64 -i --txqflags=0xf00 '
                        '--disable-hw-vlan --nb-cores=2, --txq=1 --rxq=1 --rxd=512 --txd=512']

TEST_PARAMS = {'TRAFFICGEN_PKT_SIZES':(64,1500), 'TRAFFICGEN_DURATION':15, 'TRAFFICGEN_LOSSRATE':0}

# Update your Trex trafficgen info below
TRAFFICGEN_TREX_HOST_IP_ADDR = '$TRAFFICGEN_TREX_HOST_IP_ADDR'
TRAFFICGEN_TREX_USER = 'root'
# TRAFFICGEN_TREX_BASE_DIR is the place, where 't-rex-64' file is stored on Trex Server
TRAFFICGEN_TREX_BASE_DIR = '$TRAFFICGEN_TREX_BASE_DIR'
TRAFFICGEN_TREX_PORT1 = '$TRAFFICGEN_TREX_PORT1'
TRAFFICGEN_TREX_PORT2 = '$TRAFFICGEN_TREX_PORT2'
TRAFFICGEN_TREX_LINE_SPEED_GBPS = '$TRAFFICGEN_TREX_LINE_SPEED_GBPS'
TRAFFICGEN = 'Trex'
TRAFFICGEN_TREX_LATENCY_PPS = 0
TRAFFICGEN_TREX_RFC2544_TPUT_THRESHOLD = 0.5

EOT

}

download_VNF_image() {
    if [ ! -f CentOS73.qcow2 ]
    then
        echo ""
        echo "*********************************************************************"
        echo "*** Creating VNF Image from CentOS mirror. This may take a while! ***"
        echo "*********************************************************************"
        echo ""

        git clone https://github.com/ctrautma/VSPerfBeakerInstall.git &>VNFCreate.log
        chmod +x VSPerfBeakerInstall/vmcreate.sh
        yum install -y virt-install libvirt &>>VNFCreate.log
        systemctl start libvirtd

        enforce_status=`getenforce`

        setenforce permissive

        LOCATION="http://mirror.centos.org/centos/7/os/x86_64/"
        CPUS=3
        DEBUG="no"
        VIOMMU="NO"

        vm=master
        bridge=virbr0
        master_image=master.qcow2
        image_path=/var/lib/libvirt/images/
        dist=CentOS73
        location=$LOCATION

        extra="ks=file:/$dist-vm.ks"

        master_exists=`virsh list --all | awk '{print $2}' | grep master`
        if [ -z $master_exists ]; then
            master_exists='None'
        fi

        if [ $master_exists == "master" ]; then
            virsh destroy $vm 2>/dev/null
            virsh undefine $vm
        fi

        echo deleting master image
        /bin/rm -f $image_path/$master_image

        cat << KS_CFG > $dist-vm.ks
# System authorization information
auth --enableshadow --passalgo=sha512

# Use network installation
url --url=$location

# Use text mode install
text
# Run the Setup Agent on first boot
firstboot --enable
ignoredisk --only-use=vda
# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
# System language
lang en_US.UTF-8

# Network information
network  --bootproto=dhcp --device=eth0 --ipv6=auto --activate
# Root password
rootpw  redhat
# Do not configure the X Window System
skipx
# System timezone
timezone US/Eastern --isUtc --ntpservers=10.16.31.254,clock.util.phx2.redhat.com,clock02.util.phx2.redhat.com
# System bootloader configuration
bootloader --location=mbr --timeout=5 --append="crashkernel=auto rhgb quiet console=ttyS0,115200"
# Partition clearing information
autopart --type=plain
clearpart --all --initlabel --drives=vda
zerombr

%packages
@base
@core
@network-tools
%end

%post

yum install -y tuna git nano ftp wget sysstat 1>/root/post_install.log 2>&1
git clone https://github.com/ctrautma/vmscripts.git /root/vmscripts 1>/root/post_install.log 2>&1
mv /root/vmscripts/* /root/. 1>/root/post_install.log 2>&1
rm -RF /root/vmscripts 1>/root/post_install.log 2>&1
if [ "$VIOMMU" == "NO" ]; then
    /root/setup_rpms.sh 1>/root/post_install.log 2>&1
elif [ "$VIOMMU" == "YES" ]; then
    /root/setup_rpms.sh -v 1>/root/post_install.log 2>&1
fi

%end

shutdown

KS_CFG

        qemu-img create -f qcow2 $image_path/$master_image 100G &>>VNFCreate.log
        virsh list --all | grep master && virsh undefine master &>>VNFCreate.log

        if [ $DEBUG == "yes" ]; then
        virt-install --name=$vm\
             --virt-type=kvm\
             --disk path=$image_path/$master_image,format=qcow2,,size=3,bus=virtio\
             --vcpus=$CPUS\
             --ram=4096\
             --network bridge=$bridge\
             --graphics none\
             --extra-args="$extra"\
             --initrd-inject=$dist-vm.ks\
             --location=$location\
             --noreboot\
                 --serial pty\
                 --serial file,path=/tmp/$vm.console
        else
        virt-install --name=$vm\
                 --virt-type=kvm\
                 --disk path=$image_path/$master_image,format=qcow2,,size=3,bus=virtio\
                 --vcpus=$CPUS\
                 --ram=4096\
                 --network bridge=$bridge\
                 --graphics none\
                 --extra-args="$extra"\
                 --initrd-inject=$dist-vm.ks\
                 --location=$location\
                 --noreboot\
                 --serial pty\
                 --serial file,path=/tmp/$vm.console &>> VNFCreate.log
        fi

        rm $dist-vm.ks

        setenforce $enforce_status

        mv /var/lib/libvirt/images/master.qcow2 ~/vswitchperf/CentOS73.qcow2
    fi
    echo ""

}

fail() {
    # Param 1, Fail Header
    # Param 2, Fail Message

    echo ""
    echo "!!! $1 FAILED !!!"
    echo "!!! $2 !!!"
    echo ""
    exit 1

}

git_clone_vsperf() {
    if ! [ -d "vswitchperf" ]
    then
        echo "*** Cloning OPNFV VSPerf project ***"

        yum install -y git &>>vsperf_clone.log
        git clone https://gerrit.opnfv.org/gerrit/vswitchperf &>>vsperf_clone.log
    fi
    cd vswitchperf
    git checkout -f I8148deba9039c3a0feb6394d6671aa10c5afaf0a&>>vsperf_clone.log # Euphrates release
    git pull https://gerrit.opnfv.org/gerrit/vswitchperf refs/changes/61/43061/1 # T-Rex SRIOV patch

}

run_ovs_dpdk_tests() {

    echo ""
    echo "***********************************************************"
    echo "*** Running 64/1500 Bytes 2PMD OVS/DPDK PVP VSPerf TEST ***"
    echo "***********************************************************"
    echo ""

scl enable python33 - << \EOF
source /root/vsperfenv/bin/activate
python ./vsperf pvp_tput &> vsperf_pvp_2pmd.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid

    if [[ `grep "Overall test report written to" vsperf_pvp_2pmd.log` ]]
    then

        echo ""
        echo "########################################################"

        mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" vsperf_pvp_2pmd.log | awk '{print $11}' )
        if [ "${array[0]%%.*}" -gt 3400000 ]
        then
            echo "# 64   Byte 2PMD OVS/DPDK PVP test result: ${array[0]} #"
        else
            echo "# 64 Bytes 2 PMD OVS/DPDK PVP failed to reach required 3.5 Mpps got ${array[0]} #"
        fi

        if [ "${array[1]%%.*}" -gt 1500000 ]
        then
            echo "# 1500 Byte 2PMD OVS/DPDK PVP test result: ${array[1]} #"
        else
            echo "# 1500 Bytes 2 PMD OVS/DPDK PVP failed to reach required 1.5 Mpps got ${array[1]} #"
        fi

        echo "########################################################"
        echo ""

        if [ "${array[0]%%.*}" -lt 3400000 ] || [ "${array[1]%%.*}" -lt 1500000 ]
        then
            fail "64/1500 Byte 2PMD PVP" "Failed to achieve required pps on tests"
        fi
    else
        echo "!!! VSPERF Test Failed !!!!"
        fail "Error on VSPerf test" "VSPerf test failed. Please check log at /root/vswitchperf/vsperf_pvp_2pmd.log"
    fi

    echo ""
    echo "***********************************************************"
    echo "*** Running 64/1500 Bytes 2PMD OVS/DPDK PVP VSPerf TEST ***"
    echo "***********************************************************"
    echo ""

scl enable python33 - << \EOF
source /root/vsperfenv/bin/activate
python ./vsperf pvp_tput --test-params="VSWITCH_PMD_CPU_MASK=$PMD4MASK" &> vsperf_pvp_4pmd.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid

    if [[ `grep "Overall test report written to" vsperf_pvp_4pmd.log` ]]
    then

        echo ""
        echo "########################################################"

        mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" vsperf_pvp_4pmd.log | awk '{print $11}' )
        if [ "${array[0]%%.*}" -gt 3400000 ]
        then
            echo "# 64   Byte 2PMD OVS/DPDK PVP test result: ${array[0]} #"
        else
            echo "# 64 Bytes 2 PMD OVS/DPDK PVP failed to reach required 3.5 Mpps got ${array[0]} #"
        fi

        if [ "${array[1]%%.*}" -gt 1500000 ]
        then
            echo "# 1500 Byte 2PMD OVS/DPDK PVP test result: ${array[1]} #"
        else
            echo "# 1500 Bytes 2 PMD OVS/DPDK PVP failed to reach required 1.5 Mpps got ${array[1]} #"
        fi

        echo "########################################################"
        echo ""

        if [ "${array[0]%%.*}" -lt 3400000 ] || [ "${array[1]%%.*}" -lt 1500000 ]
        then
            fail "64/1500 Byte 2PMD PVP" "Failed to achieve required pps on tests"
        fi
    else
        echo "!!! VSPERF Test Failed !!!!"
        fail "Error on VSPerf test" "VSPerf test failed. Please check log at /root/vswitchperf/vsperf_pvp_4pmd.log"
    fi

    echo ""
    echo "*****************************************************************"
    echo "*** Running 2000/9000 Bytes 2PMD Phy2Phy OVS/DPDK VSPerf TEST ***"
    echo "*****************************************************************"
    echo ""

scl enable python33 - << \EOF
source /root/vsperfenv/bin/activate
python ./vsperf phy2phy_tput --test-params="TRAFFICGEN_PKT_SIZES=2000,9000; VSWITCH_JUMBO_FRAMES_ENABLED=True" &> vsperf_phy2phy_2pmd_jumbo.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid

    if [[ `grep "Overall test report written to" vsperf_phy2phy_2pmd_jumbo.log` ]]
    then

        echo ""
        echo "########################################################"

        mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" vsperf_phy2phy_2pmd_jumbo.log | awk '{print $11}' )
        if [ "${array[0]%%.*}" -gt 1100000 ]
        then
            echo "# 2000 Byte 2PMD OVS/DPDK Phy2Phy test result: ${array[0]} #"
        else
            echo "# 2000 Bytes 2 PMD OVS/DPDK PVP failed to reach required 1.1 Mpps got ${array[0]} #"
        fi

        if [ "${array[1]%%.*}" -gt 250000 ]
        then
            echo "# 9000 Byte 2PMD OVS/DPDK PVP test result: ${array[1]} #"
        else
            echo "# 9000 Bytes 2 PMD OVS/DPDK PVP failed to reach required 250 Kpps got ${array[1]} #"
        fi

        echo "########################################################"
        echo ""

        if [ "${array[0]%%.*}" -lt 1100000 ] || [ "${array[1]%%.*}" -lt 250000 ]
        then
            fail "2000/9000 Byte 2PMD PVP" "Failed to achieve required pps on tests"
        fi
    else
        echo "!!! VSPERF Test Failed !!!!"
        fail "Error on VSPerf test" "VSPerf test failed. Please check log at /root/vswitchperf/vsperf_pvp_2pmd_jumbo.log"
    fi

}

run_ovs_kernel_tests() {
    echo ""
    echo "********************************************************"
    echo "*** Running 64/1500 Bytes PVP OVS Kernel VSPerf TEST ***"
    echo "********************************************************"
    echo ""

scl enable python33 - << \EOF
source /root/vsperfenv/bin/activate
python ./vsperf pvp_tput --vswitch=OvsVanilla --vnf=QemuVirtioNet --test-params="TRAFFICGEN_LOSSRATE=0.002" &> vsperf_pvp_ovs_kernel.log &
EOF

    sleep 2
    vsperf_pid=`pgrep -f vsperf`

    spinner $vsperf_pid

    if [[ `grep "Overall test report written to" vsperf_pvp_ovs_kernel.log` ]]
    then

        echo ""
        echo "########################################################"

        mapfile -t array < <( grep "Key: throughput_rx_fps, Value:" vsperf_pvp_ovs_kernel.log | awk '{print $11}' )
        if [ "${array[0]%%.*}" -gt 400000 ]
        then
            echo "# 64   Byte OVS Kernel PVP test result: ${array[0]} #"
        else
            echo "# 64 Bytes OVS Kernel PVP failed to reach required 400 Kpps got ${array[0]} #"
        fi

        if [ "${array[1]%%.*}" -gt 300000 ]
        then
            echo "# 1500 Byte OVS Kernel PVP test result: ${array[1]} #"
        else
            echo "# 1500 Bytes OVS Kernel PVP failed to reach required 300 Kpps got ${array[0]} #"
        fi

        echo "########################################################"
        echo ""

        if [ "${array[0]%%.*}" -lt 400000 ] || [ "${array[1]%%.*}" -lt 300000 ]
        then
            fail "64/1500 OVS Kernel PVP" "Failed to achieve required pps on tests"
        fi
    else
        echo "!!! VSPERF Test Failed !!!!"
        fail "Error on VSPerf test" "VSPerf test failed. Please check log at /root/vswitchperf/vsperf_pvp_ovs_kernel.log"
    fi

}

spinner() {
if [ $# -eq 1 ]
then
    pid=$1
else
    pid=$! # Process Id of the previous running command
fi

spin[0]="-"
spin[1]="\\"
spin[2]="|"
spin[3]="/"

echo -n "${spin[0]}"
while kill -0 $pid 2>/dev/null
do
  for i in "${spin[@]}"
  do
        echo -ne "\b$i"
        sleep 0.1
  done
done

}

vsperf_make() {
    if [ ! -f ~/vsperf_install.log ]
    then
        echo "*** Running VSPerf installation ***"

        # since we are using rpms and due to build issues only run T-Rex build
        sed -i s/'SUBDIRS += l2fwd'/'#SUBDIRS += l2fwd'/ src/Makefile
        sed -i s/'SUBDIRS += dpdk'/'#SUBDIRS += dpdk'/ src/Makefile
        sed -i s/'SUBDIRS += qemu'/'#SUBDIRS += qemu'/ src/Makefile
        sed -i s/'SUBDIRS += ovs'/'#SUBDIRS += ovs'/ src/Makefile
        sed -i s/'SUBDIRS += vpp'/'#SUBDIRS += vpp'/ src/Makefile
        sed -i s/'SUBBUILDS = src_vanilla'/'#SUBBUILDS = src_vanilla'/ src/Makefile
        if ! [ -d "./systems/rhel/$VERSION_ID" ]
        then
            cp -R systems/rhel/7.2 systems/rhel/$VERSION_ID
        fi
        cd systems
        ./build_base_machine.sh &> /root/vsperf_install.log &
        spinner
        cd ..

        if ! [[ `grep "finished making all" /root/vsperf_install.log` ]]
        then
            fail "VSPerf Install" "VSPerf installation failed, please check log"
        fi
    fi
}

main() {
# run all checks
OS_checks
hugepage_checks
conf_checks
config_file_checks
nic_card_check
rpm_check
network_connection_check
ovs_running_check
# finished running checks

git_clone_vsperf
vsperf_make
customize_VSPerf_code
download_VNF_image
download_conf_files
run_ovs_dpdk_tests
run_ovs_kernel_tests
}

if [ "${1}" != "--source-only" ]
then
    main "${@}"
fi

