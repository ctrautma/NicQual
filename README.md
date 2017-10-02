# Platform QE Nic Qualification Script

The QE Scripts are three separate scripts that all must pass.

The functional test script runs a plethora of tests to verify NICs pass functional requirements.

The performance based tests use an upstream project called VSPerf from OPNFV to test performance
using very basic flows rules and parameters. This is broken into two scripts, the first script
will test phy2phy, and PVP scenarios. The second script requires SR-IOV to be enabled on the NICs
in test.

The performance based tests require servers. One server will have TREX installed, the other will
be a clean install system running RHEL 7.4 or greater. The servers should be wired back to back
from the test NICs to the output NICs of the T-Rex server.

The server with the NICs under test must have 9 available Hyperthreads on the NIC Numa to run all
tests correctly. Do not use CPU 0 or its paired hyperthread for PMD or VCPU assignments.

The T-Rex generator should be setup as per the following instructions

Download the Trex latest release from here:

     git clone https://github.com/cisco-system-traffic-generator/trex-core

After downloading, Run configure and build

     cd trex-core/linux_dpdk

    ./b configure   (run only once)

    ./b build

NOTE: T-Rex server may need gcc, zlib-devel, and dpdk rpms installed to build correctly.

Next step is to create a minimum configuration file. It can be created by script ``dpdk_setup_ports.py``.
The script with parameter ``-i`` will run in interactive mode and it will create file ``/etc/trex_cfg.yaml``.

    cd trex-core/scripts

    sudo ./dpdk_setup_ports.py -i

Or example of configuration file can be found at location below, but it must be updated manually:

    cp trex-core/scripts/cfg/simple_cfg /etc/trex_cfg.yaml

After compilation and configuration trex server must be active in stateless mode. It is neccesary for proper connection
between Trex server and VSPERF.

    cd trex-core/scripts/

    ./t-rex-64 -i

NOTE: One will need to set up ssh login to not use passwords between the server
running Trex and the device under test (running the VSPERF test
infrastructure). This is because VSPERF on one server uses 'ssh' to
configure and run Trex upon the other server.

One can set up this ssh access by doing the following on both servers:

    ssh-keygen -b 2048 -t rsa

    ssh-copy-id <other server>

On the Server running the test everything is executed from the Perf-Verify.sh
script. It runs various checks to verify that the configuration is valid.

The following steps must be completed for the script to execute correctly.

    1. Iommu mode must be enabled in proc/cmdline to support VFIO driver for DPDK
       - Edit the /etc/default/grub
       - Add intel_iommu=on iommu=pt to GRUB_CMDLINE_LINUX
       - Run "grub2-mkconfig -o /boot/grub2/grub.cfg"
       - reboot

    2. 1G hugepages must be enabled and enough pages available for DPDK and a Guest

    to run. Recommend at least 8 Hugepages of 1G in size.
       - Edit /etc/default/grub
       - Add default_hugepagesz=1G hugepagesz=1G hugepages=8 to GRUB_CMDLINE_LINUX
       - Run "grub2-mkconfig -o /boot/grub2/grub.cfg"
       - reboot

    3. CPU-partitioning tuned-adm profile must be active,

    tuned-profiles-cpu-partitioning.noarch package may need to be installed.
       - yum install cpu-partitioning profile
       - edit /etc/tuned/cpu-partitioning-variables.conf
       - add CPUs to isolate which will be used for PMDs and VCPUs
       - apply profile "tuned-adm profile cpu-partitioning"
       - reboot

    If you wish to apply isolated CPUs to all on the NIC Numa you can use the below code to do so.

        NIC1=<NIC1 Dev name> # such as p4p1
        NIC2=<NIC2 Dev name> # such as p4p2

        NIC1_PCI_ADDR=`ethtool -i $NIC1 | awk /bus-info/ | awk {'print $2'}`
        NIC2_PCI_ADDR=`ethtool -i $NIC2 | awk /bus-info/ | awk {'print $2'}`
        NICNUMA=`cat /sys/class/net/$NIC1/device/numa_node`

        ISOLCPUS=`lscpu | grep "NUMA node$NICNUMA" | awk '{print $4}'`

        if [ `echo $ISOLCPUS | awk /'^0,'/` ]
            then
            ISOLCPUS=`echo $ISOLCPUS | cut -c 3-`
        fi

        # ECHO your ISOLCPUS to make sure they are accurate.

        echo $ISOLCPUS

        echo -e "isolated_cores=$ISOLCPUS" >> /etc/tuned/cpu-partitioning-variables.conf
        tuned-adm profile cpu-partitioning
        reboot

    4. Openvswitch, dpdk, dpdk-tools, and qemu-kvm-rhev rpms must be installed locally from appropriate channels

    5. The current user must be root

    6. The OS must be RHEL 7.4 or above.

    7. The server must have an internet connection to pull files from public servers for the VNF image to be downloaded

    8. The Perf-Verify.conf file must be setup. It is a simple bash text file that

    requires NIC, CPU assignment and T-Rex server info.

    9. For SR-IOV script to run SR-IOV must be enabled on the NIC to test and the info in the Perf-Verify.conf must be

    completed.

After completing all setup steps run Perf-Verify.sh from the git cloned folder

If all tests pass for OVS/DPDK and OVS Kernel enable SR-IOV on the NIC and run Perf-Verify-sriov.sh

Once all Performance tests have passed next prepare to run the functional test qualification script.

a) Prepare two machines with the tested RHEL disto installed
     The topology for physical connection can be found in rh_nic_cert.sh

  b) copy the generated rh_nic_cert.tar to two machines and decompress the package

  c) go to the directory rh_nic_cert

  d) customize the configuration in rh_nic_cert.sh by your test environment
     The detail for each configuration can be found in rh_nic_cert.sh

     i) Run part of test
        QE_SKIP_TEST: used to list the skipped test cases
        QE_TEST: used to list the specific test to run

        NOTE: QE_SKIP_TEST has a higher priority than QE_TEST, that is, if a test is listed in QE_SKIP_TEST, the test will be skipped even it's listed in QE_TESt also

     ii) Switch supported
        The bonding test cases will use a switch between the two linux machines. Now in the test script Cisco and Juniper switch are supported.
        In your test envrionment, if Cisco or Juniper switch is used, you can define your switch in bin/swlist.
        If other switch is used, one option is that you can skip the bonding test by listing $BONDING_TEST in $QE_SKIP_TEST in rh_nic_cert.sh, the other option is to extend the switch script
        lib/lib_swcfg.sh is the implementation of all functions used by the test to control switch.

  e) run rh_nic_cert.sh

COMING SOON....

  1. Pass/Fail for higher bandwidths 25/40/50/100

  2. Better error checking
