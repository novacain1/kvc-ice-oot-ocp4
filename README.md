# Intel ice driver KVC implementation on OpenShift 4 Realtime
Repository to leverage Kmods via Containers (KVC) pattern to effectively utilize Intel's Out of Tree ice Network Interface driver for E810 series cards in an OpenShift 4 environment.  This specific repository targets the Realtime version of Red Hat Enterprise Linux CoreOS (commonly abbreviated as RHCOS).  More details on provisioning a node with real-time capabilities are avaiable in the OpenShift documentation [here](https://docs.openshift.com/container-platform/4.7/scalability_and_performance/cnf-performance-addon-operator-for-low-latency-nodes.html#performance-addon-operator-provisioning-worker-with-real-time-capabilities_cnf-master).

Currently tested with OpenShift version `4.7.9` with version `1.5.8` of the Intel ice driver.

> :heavy_exclamation_mark: *Red Hat support cannot assist with problems with this Repo*!
> :heavy_exclamation_mark: *Intel supports the ice driver on sourceforge.net*!

## Background

This project is used to build a MachineConfig object, *ice-mc.yaml*, that installs a newer version of the Intel ice driver in OpenShift 4.7 nodes of your choosing.

This project uses the [kmods-via-containers](https://github.com/openshift-psap/kmods-via-containers) projects to load kernel modules using containers.  The [kvc-ice-kmod](https://github.com/novacain1/kvc-ice-kmod) repository is a companion to this repo and implements some of the *kmods-via-containers* project requirements.

Credit to Aaron Smith (https://github.com/atyronesmith/) for the original work that this implementation is based on!

The *build.sh* script enables the **Cluster-Wide Entitled Builds on OpenShift
** method as outlined in this [blog](https://www.openshift.com/blog/how-to-use-entitled-image-builds-to-build-drivercontainers-with-ubi-on-openshift)

## Prerequisites

Pre-requisites include copying the reader's entitlement PEM files into the directory called **certdir**.  This is easily accomplished by using a RHEL8 host as a builder machine, subscribe it to [Red Hat Subscription Management](https://access.redhat.com/solutions/253273), and copy files from the directory `/etc/pki/entitlement` to **certdir**.

As an alternative (and if you are not a Red Hat Partner using a Not-for-Resale subscription, also known as an NFR), one can attach a *Red Hat Developer Subscription for Individuals* subscription to a virtual system, and download the certificates from your [Red Hat Customer Portal](access.redhat.com).  Place the entitlement_certifications/.pem files in **certdir**.

## Building and Installing

To build the *ice-mc.yaml* file:

```Shell
    ./build.sh build certdir
```

The build directory in this repository will be populated, and the file *ice-mc.yaml* should be created if the build was successful.  This YAML needs to be fed to the cluster in order to use the updated ice driver.

```Shell
    oc create -f ice-mc.yaml
```

At this point, the worker nodes will go into a NotReady,SchedulingDisabled state for a while as the MachineConfig object is installed and the nodes are rebooted.

After the real-time workers return to normal, you can check that the new driver is installed:

    [root@dcain-oc-client ~] oc debug nodes/worker1
    Starting pod/worker1-debug ...
    To use host binaries, run `chroot /host`
    sh-4.4# chroot /host
    sh-4.4# cat /sys/bus/pci/drivers/ice/module/version
    1.5.8

## Uninstalling or removing
Simply delete the MachineConfig file that was created earlier.  This will restore the inbox driver on the nodes in question.

```Shell
    oc delete -f ice-mc.yaml
```
