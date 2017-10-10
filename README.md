# Platform QE Nic Qualification Script

The QE Scripts are three separate scripts that all must pass.

The functional test script runs a plethora of tests to verify NICs pass functional requirements.

The performance based tests use an upstream project called VSPerf from OPNFV to test performance
using very basic flows rules and parameters. This is broken into two scripts, the first script
will test phy2phy, and PVP scenarios. The second script requires SR-IOV to be enabled on the NICs
in test.

The performance based tests require two servers. One server will have TREX installed, the other
will be a clean install system running RHEL 7.4 or greater. The servers should be wired back to back
from the test NICs to the output NICs of the T-Rex server. These tests use two NIC ports on the DUT
and two ports on the T-Rex which are connected as shown below. The two NIC ports on the DUT must be
the brand and type of NICs which are to be qualified. The first set of performance tests use a
topology as seen below.

                                                             _
       +---------------------------------------------------+  |
       |                                                   |  |
       |   +-------------------------------------------+   |  |
       |   |                 Application               |   |  |
       |   +-------------------------------------------+   |  |
       |       ^                                  :        |  |
       |       |                                  |        |  |  Guest
       |       :                                  v        |  |
       |   +---------------+           +---------------+   |  |
       |   | logical port 0|           | logical port 1|   |  |
       +---+---------------+-----------+---------------+---+ _|
               ^                                  :
               |                                  |
               :                                  v         _
       +---+---------------+----------+---------------+---+  |
       |   | logical port 0|          | logical port 1|   |  |
       |   +---------------+          +---------------+   |  |
       |       ^                                  :       |  |
       |       |                                  |       |  |  Host
       |       :                                  v       |  |
       |   +--------------+            +--------------+   |  |
       |   |   phy port   |  vSwitch   |   phy port   |   |  |
       +---+--------------+------------+--------------+---+ _|
                  ^                           :
                  |                           |
                  :                           v
       +--------------------------------------------------+
       |                                                  |
       |                traffic generator                 |
       |                                                  |
       +--------------------------------------------------+

All traffic on these tests are bi-directional and the results are calculated as a total of the
sum of both ports in frames per second.

An initial test at the host doing loopback is run to verify the configuration.

The server with the NICs under test must have 9 available Hyperthreads on the NIC Numa to run all
tests correctly. Do not use CPU 0 or its paired hyperthread for PMD or VCPU assignments.

If you have already setup the T-Rex generator as per the initial 24 hour PVP script then you can
skip the setup instructions below for T-Rex.

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

    ** NOTE ** Make sure to leave the password field blank.

    ssh-copy-id <other server>

On the Server running as the DUT everything is executed from the Perf-Verify.sh
script. It runs various checks to verify that the configuration is valid.

The following steps must be completed for the script to execute correctly or some
of the checks may fail which will exit the script with an error.


    1. trex must be running on the trex server. If the server is not running the
       traffic generator program, the tests will fail.

       The following command should be run on the trex server from the scripts folder

       ./t-rex-64 -i

       You should now see the server start up and go to a text interface screen
       that will report output and input traffic.

    2. Iommu mode must be enabled in proc/cmdline to support VFIO driver for DPDK
       - Edit the /etc/default/grub
       - Add intel_iommu=on iommu=pt to GRUB_CMDLINE_LINUX
       - Run "grub2-mkconfig -o /boot/grub2/grub.cfg"
       - reboot

    3. 1G hugepages must be enabled and enough pages available for DPDK and a Guest

    to run. Recommend at least 8 Hugepages of 1G in size.
       - Edit /etc/default/grub
       - Add default_hugepagesz=1G hugepagesz=1G hugepages=8 to GRUB_CMDLINE_LINUX
       - Run "grub2-mkconfig -o /boot/grub2/grub.cfg"
       - reboot

    4. CPU-partitioning tuned-adm profile must be active,

    tuned-profiles-cpu-partitioning.noarch package may need to be installed.
       - yum install tuned-profiles-cpu-partitioning
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

        # ECHO your ISOLCPUS to make sure they are accurate. This should never include CPU 0 but the
        # above code deals with this.

        echo $ISOLCPUS

        echo -e "isolated_cores=$ISOLCPUS" >> /etc/tuned/cpu-partitioning-variables.conf
        tuned-adm profile cpu-partitioning
        reboot

    5. Openvswitch, dpdk, dpdk-tools, and qemu-kvm-rhev rpms must be installed locally from appropriate channels

       The subscription channels isntalled from the previous PVP script should provide access to these rpms.

    6. The current user must be root

    7. The OS must be RHEL 7.4 or above.

    8. The server must have an internet connection to pull files from public servers for the VNF image to be downloaded

    9. The Perf-Verify.conf file must be setup. It is a simple bash text file that

    requires NIC, CPU assignment and T-Rex server info.

    To properly setup PMD and VCPU assignments consider the following:

        a. You will need 2 Core/4 Hyper thread pairs for OVS/DPDK PMD threads. For guests you will need a total of 5
           Hyperthreads spread amongst 3 Cores.

        b. For example using utilities such as lscpu, lstopo-no-graphic, or cpu_layout.py from the dpdk.org repository
           we can find core hyperthread pairs to use on the same numa as the NIC we are testing.

           # ======================================================================
           # Core and Socket Information (as reported by '/sys/devices/system/cpu')
           # ======================================================================
           #
           # cores =  [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13]
           # sockets =  [0, 1]
           #
           #         Socket 0        Socket 1
           #         --------        --------
           # Core 0  [0, 24]         [1, 25]
           # Core 1  [2, 26]         [3, 27]
           # Core 2  [4, 28]         [5, 29]
           # Core 3  [6, 30]         [7, 31]
           # Core 4  [8, 32]         [9, 33]
           # Core 5  [10, 34]        [11, 35]
           # Core 8  [12, 36]        [13, 37]
           # Core 9  [14, 38]        [15, 39]
           # Core 10 [16, 40]        [17, 41]
           # Core 11 [18, 42]        [19, 43]
           # Core 12 [20, 44]        [21, 45]
           # Core 13 [22, 46]        [23, 47]

           We can locate our NUMA location for our NIC by running the following command

           cat /sys/class/net/<device id>/device/numa_node

           If our NIC was p6p1 we would identify it on NUMA 0.

           cat /sys/class/net/p6p1/device/numa_node
           0

           Since we should never use CPU 0 or its hyperthread pair we will use cores 2, 4, and 28 for our VCPUs.

           The second and third VCPU should be a core / Hyperthread pair and VCPU 1 on its own Core. This is
           because the first VCPU will be used for all activities outside of the PMD threads for TESTPMD inside
           of the VNF. For the 2 queue test a second pair of VCPUs must be assigned. We could use 6 and 30 as
           VCPUs 4 and 5.

           We must set a PMD mask for OVS/DPDK. We will do a 2 PMD mask for single queue tests and a 4 PMD mask
           for the 2 queue test.

           Since we do not want VCPUs and host DPDK PMDs to run on the same Hyperthreads we will use CPUs 18 and 42
           for our 2 PMD MASK. For the 4 PMD mask we will add 16 and 40. Doing a binary to hex conversion this means
           we would set our 2 PMD mask to 040000040000 and our 4 PMD mask to 050000050000.

    10. For SR-IOV script to run SR-IOV must be enabled on the NIC to test and the info in the Perf-Verify.conf must be

    completed.

    SR-IOV will do passthrough to the guest using the VFs specified as shown in the below topology

       +---------------------------------------------------+  |
       |                                                   |  |
       |   +-------------------------------------------+   |  |
       |   |                 Application               |   |  |
       |   +-------------------------------------------+   |  |
       |       ^                                  :        |  |
       |       |                                  |        |  |  Guest
       |       :                                  v        |  |
       |   +---------------+           +---------------+   |  |
       |   | logical port 0|           | logical port 1|   |  |
       +---+---------------+-----------+---------------+---+ _|
               ^                                  :
               |                                  |
               :                                  v         _
       +---+---------------+----------+---------------+---+  |
       |                                                  |  |
       |                                                  |  |
       |                                                  |  |
       |                                                  |  |  Host
       |                                                  |  |
       |   +--------------+            +--------------+   |  |
       |   |   vf  port   |            |   vf  port   |   |  |
       +---+--------------+------------+--------------+---+ _|
                  ^                           :
                  |                           |
                  :                           v
       +--------------------------------------------------+
       |                                                  |
       |                traffic generator                 |
       |                                                  |
       +--------------------------------------------------+


After completing all setup steps run Perf-Verify.sh from the git cloned folder

If all tests pass for OVS/DPDK and OVS Kernel enable SR-IOV on the NIC and run Perf-Verify-sriov.sh

Once all Performance tests have passed next prepare to run the functional test qualification script.

a) Prepare two machines with the tested RHEL disto installed
     The topology for physical connection can be found in rh_nic_cert.sh

  b) copy the generated rh_nic_cert.tar to two machines and decompress the package with "tar -xvf rh_nic_cert.tar"

  c) go to the directory rh_nic_cert on both systems

  d) customize the configuration in rh_nic_cert.sh by your test environment on both systems
     The detail for each configuration can be found in rh_nic_cert.sh

     i) Run part of test
        QE_SKIP_TEST: used to list the skipped test cases
        QE_TEST: used to list the specific test to run

        NOTE: QE_SKIP_TEST has a higher priority than QE_TEST, that is, if a test is listed in QE_SKIP_TEST, the test will be skipped even it's listed in QE_TESt also

     ii) Switch supported
        The bonding test cases will use a switch between the two linux machines. Now in the test script Cisco and Juniper switch are supported.
        In your test environment, if Cisco or Juniper switch is used, you can define your switch in bin/swlist.
        If other switch is used, one option is that you can skip the bonding test by listing $BONDING_TEST in $QE_SKIP_TEST in rh_nic_cert.sh, the other option is to extend the switch script
        lib/lib_swcfg.sh is the implementation of all functions used by the test to control switch.

  e) run rh_nic_cert.sh on both systems at the same time as close as possible

COMING SOON....

  1. Pass/Fail for higher bandwidths 25/40/50/100

  2. Better error checking

  3. Log collection upon completion

  4. Add instructions for creating custom VNF image
