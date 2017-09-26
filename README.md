# Platform QE Nic Qualification Script

Requires two servers, one for running the tests, and one for running the T-Rex
Traffic Generator.

T-Rex generator should be setup as per the following instructions

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
       - Add intel_iommu=on iommu=pt
       - Run "grub2-mkconfig -o /boot/grub2/grub.cfg"
       - reboot

    2. 1G hugepages must be enabled and enough pages available for DPDK and a Guest

    to run. Recommend at least 8 Hugepages of 1G in size.
       - Edit /etc/default/grub
       - Add default_hugepagesz=1G hugepagesz=1G hugepages=8
       - Run "grub2-mkconfig -o /boot/grub2/grub.cfg"
       - reboot

    3. CPU-partitioning tuned-adm profile must be active,

    tuned-profiles-cpu-partitioning.noarch package may need to be installed.
       - yum install cpu-partitioning profile
       - edit /etc/tuned/cpu-partitioning-variables.conf
       - add CPUs to isolate
       - apply profile "tuned-adm profile cpu-partitioning"
       - reboot

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
