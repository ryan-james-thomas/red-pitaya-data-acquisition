# Description

This is a simple data acquisition system for the Red Pitaya 14-bit development board.  It collects and stores data from the two ADCs at variable sample rates for later retrieval.  There are two methods of storage.  The first method stores up to 16384 samples on each ADC in a block memory; this data capture can be triggered on either hardware or software.  The second method stores data in a 512 address FIFO buffer which can be read continuously via an AXI interface, which means it can record as much data as there is storage on the Red Pitaya memory card.  Both methods can reduce the sampling rate by averaging over 2^N samples.

The external trigger is currently set to be DIO7_N on the [E1 connector](https://redpitaya.readthedocs.io/en/latest/developerGuide/hardware/125-14/extent.html#extension-connector).


# Set up

## Starting the Red Pitaya

Connect the Red Pitaya (RP) to power via the USB connector labelled PWR (on the underside of the board), and connect the device to the local network using an ethernet cable.  Log into the device using SSH with the user name `root` and password `root` using the hostname `rp-{MAC}.local` where `{MAC}` is the last 6 characters in the device's MAC address - this will be printed on the ethernet connector of the device.

### First use

Copy over the files in the 'software/' directory ending in '.py', the file 'get_ip.sh', and the file 'saveScanData.c' using either `scp` (from a terminal on your computer) or your favourite GUI (I recommend WinSCP for Windows).  You will also need to copy over the file 'fpga/system_wrapper.bit' which is the device configuration file.  If using `scp` from the command line, navigate to the main project directory on your computer and use
```
scp fpga/system_wrapper.bit software/*.py software/get_ip.sh software/*.c root@rp-{MAC}.local:/root/
```
and give your password as necessary.  You can move these files to a different directory on the RP after they have been copied.

Next, change the execution privileges of `get_ip.sh` using `chmod a+x get_ip.sh`.  Check that running `./get_ip.sh` produces a single IP address.  If it doesn't, run the command `ip addr` and look for an IP address that isn't `127.0.0.1` (which is the local loopback address).  There may be more than one IP address -- you're looking for one that has tags 'global' and 'dynamic'.  Here is the output from one such device:
```
root@rp-f0919a:~# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 00:26:32:f0:91:9a brd ff:ff:ff:ff:ff:ff
    inet 169.254.176.82/16 brd 169.254.255.255 scope link eth0
       valid_lft forever preferred_lft forever
    inet 192.168.1.109/24 brd 192.168.1.255 scope global dynamic eth0
       valid_lft 77723sec preferred_lft 77723sec
3: sit0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN group default qlen 1
    link/sit 0.0.0.0 brd 0.0.0.0
```
In this case the one we want is the address `192.168.1.109`.  In this case, `get_ip.sh` will work because it looks for an IP address starting with `192.168`.  If your IP address starts with something else, you will need to edit the `get_ip.sh` file and change the numbers to reflect your particular network.

Finally, compile the C programs `saveData.c` and `fetchData.c` using `gcc -o saveData saveData.c` and `gcc -o fetchData fetchData.c`.  These will automatically be executable.

### After a reboot or power-on

You will need to re-configure the FPGA and start the Python socket server after a reboot.  To re-configure the FPGA run the command
```
cat system_wrapper.bit > /dev/xdevcfg
```

To start the Python socket server run
```
python3 appserver.py &
```
This should print a line telling you the job number and process ID  as, for example, `[1] 5760`, and a line telling you that it is 'Listening on' and then an address and port number.  The program will not block the command line and will run in the background as long as the SSH session is active (The ampersand & at the end tells the shell to run the program in the background).  To stop the server, run the command `fg 1` where `1` is the job number and then hit 'CTRL-C' to send a keyboard interrupt.

### After starting/restarting the SSH session

You will need to check that the socket server is running.  Run the command
```
ps -ef | grep appserver.py
```
This will print out a list of processes that match the pattern `appserver.py`.  One of these might be the `grep` process itself -- not especially useful -- but one might be the socket server.  Here's an example output:
```
root      5768  5738  7 00:59 pts/0    00:00:00 python3 appserver.py
root      5775  5738  0 01:00 pts/0    00:00:00 grep --color=auto appserver.py
```
The first entry is the actual socket server process and the second one is the `grep` process.  If you need to stop the server, and it is not in the jobs list (run using `jobs`), then you can kill the process using `kill -15 5768` where `5768` is the process ID of the process (the first number in the entry above).  

If you want the server to run you don't need to do anything.  If the server is not running, start it using `python3 appserver.py`.  

# Use

There are two separate methods of storing acquired data in this design: fixed-length memory or a FIFO that can be continuously read out.  The fixed-length memory acquisition is termed the 'fast' acquisition method, and the FIFO acquisition is termed the 'slow' method.  The major difference between these is that the 'fast' method can be triggered externally and will acquire a fixed number of samples after a programmable acquisition delay, while the 'slow' method will continuously send data to the FIFO as long as it is enabled.  If data is removed from the FIFO fast enough, one can acquire data forever.

For the fast acquisition method there are four parameters of interest:
  - Trigger edge: edge of trigger to use: either rising or falling edge
  - Log2 of the number of averages: This controls the number of averages/de-sampling of the incoming ADC data.  Data is de-sampled to a new rate of 125 MHz x 2^-N where N is setting of this parameter
  - Acquisition delay: This is the delay between when the trigger arrives and when the acquisition starts
  - Number of samples: This is the number of samples to acquire.
  - Trigger hold-off: This sets the dead time during which no triggers are accepted.

For the slow acquisition method there is only the one parameter:
  - Log2 of the number of averages: This controls the number of averages/de-sampling of the incoming ADC data.  Data is de-sampled to a new rate of 125 MHz x 2^-N where N is setting of this parameter

These parameters can be accessed via the memory-mapped AXI interface, or, alternatively, via the provided remote MATLAB interface.

# MATLAB interface

A suite of MATLAB classes can be used to interface with the device via a Python socket server.  Instantiate the parent class `DataAcquisition` using
```
dev = DataAcquisition(<IP address>);
```
where `<IP address>` is the IP address of the Red Pitaya.  Accessible properties are
  - trigEdge: Trigger edge to use: 0 for falling edge, 1 for rising edge
  - holdOff: trigger hold off in seconds
  - log2AvgsFast: log2 of the number of averages for the fast acquisition method
  - delay: delay between trigger and start of acquisition.  Must be larger than 64 ns
  - numSamples: number of samples to acquire for the fast acquisition
  - log2AvgsSlow: log2 of the number of averages for the slow acquisition method
  - lastSample: this is a *read only* parameter that indicates how many samples have been acquired by the fast method.

In addition, there is the property `jumpers` which you should set to either `lv` or `hv` depending on the setting of the actual ADC input jumpers on the device.  Currently, the software only supports having both sets of jumpers set to the same value.

Parameters are set and read using `set()` and `get()` methods like so:
```
dev.delay.set(10e-6);   %Set delay to 10 us
t = dev.delay.get();    %t is now equal to 10e-6
```
All parameters can be written to the device using the `upload()` method, and all parameters can be fetched from the device using the `fetch()` method:
```
dev.upload();   %Uploads parameters to the device
dev.fetch();    %Fetches parameters from the device
```
Individual parameters can be written to the device and read from the device using, for example,
```
dev.delay.write();
dev.delay.read();
```

Data acquired using the fast method can be read from the device using the `fetchData()` method.  When no arguments are supplied it will fetch all data that has been acquired in the last acquisition according to the property `lastSample`.  Otherwise, you can specify the number of samples using `fetchData(N)` where `N` is the number of samples.  Here's an example:
```
%Set parameters
dev.log2AvgsFast.set(0);
dev.numSamples.set(1e4);
dev.delay.set(100e-9);
dev.holdoff.set(1e-3);
dev.trigEdge.set(1);
%Upload parameters
dev.upload();
%Trigger acquisition
dev.start();
%Get data
dev.fetchData();    %Fetch all data on the device
%OR
dev.fetchData(1000);%Fetch 1000 samples
%Plot data
plot(dev.t,dev.data,'.-');
```

You can acquire data through the slow method using the `saveData()` method.  For this method, you supply the number of samples that you want to record.  I suggest making sure that the number of samples and the sampling rate are such that data acquisition is less than 10 s, otherwise the TCP/IP connection will time out.  Also, keep the number of samples below about 20,000 because it takes a long time to transfer more data.  Use this method like so:
```
dev.log2AvgsSlow.set(17);   %Sampling rate of about 1 kHz
dev.saveData(1e4);  %Acquire 10 s worth of data
plot(dev.t,dev.data,'.-');
```

# Direct control

For longer data runs using the slow method, you should call the C programs directly on the device.  The program you want here is `saveData` which has the following syntax:
```
./saveData -fm -d -n <number of samples>
```
The first set of options, `-f` or `-m`, specify how to store/save data as it is read from the FPGA.  `-m` tells the program to store data in memory as it is read from the device, while `-f` tells the program to save data directly to a file as it is read.  In principle, `-m` should be slightly faster.  Pick only one of these.

The `-d` option tells the program to print debugging information related to how long it takes to read data and the average time per read.  This can be useful if you want to know if the program is reading data faster than data is recorded on the device.

The number of samples is set using the `-n` flag followed by the number of samples.  The number of samples has no limit except for either the amount of RAM on the chip (the `-m` option) or the storage capacity of the SD card (the `-f`) option.

Data is saved to the file `SavedData.bin`.  Once you have transferred this to your computer using a file-transfer program like WinSCP (or `scp` from a terminal), you can read it into MATLAB using
```
data = DataAcquisition.loadData('SavedData.bin',dt,c);
```
where `dt` is the sample rate of the data (this is not stored with the file), and `c` is the conversion factor to use to convert from the integer values used in the FPGA to real voltages in volts.  `c` should be one of either `DataAcquisition.CONV_ADC_LV` or `DataAcquisition.CONV_ADC_HV` corresponding to the jumper settings on the device (either LV or HV).


# Creating the project

To create the Vivado project, clone the repository to a directory on your computer, open Vivado, navigate to the fpga/ directory (use `pwd` in the TCL console to determine your current directory and `cd` to navigate, just like in Bash), and then run `source make-project.tcl`.  This should create the project with no errors.  It may not correctly assign the AXI addresses, so you will need to open the address editor and assign the `PS7/AXI_Parse_0/s_axi` interface the address range `0x4000_000` to `0x7fff_ffff`.

