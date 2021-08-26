# Use

This is a bare-bones Vivado project for the Red-Pitaya/STEMlab boards.  It is meant to be a starting point for custom designs with the Red Pitaya.  HDL code is written in VHDL, and it includes modules for reading from the ADCs and writing to the DACs as well as a simplified interface for reading/writing to the device via the AXI interface.

Included in the software directory is some Python code that can be run from the command line on the Red Pitaya which will start a simple TCP/IP socket server that can be used to send and receive data from a remote computer.  First edit the shell script `get_ip.sh` so that it picks out the correct IP address, change its permissions so it can be executed (you may need to install dos2unix using `apt install dos2unix` and then run `dos2unix get_ip.sh` to make it work), and then spin up the server using
```
python3 appserver.py
```

The suite of MATLAB classes can be used to send and receive data.  Create an instance of
```
dev = DeviceControl(ip_addr);
```
where `ip_addr` is the IP address of the Red Pitaya.  You can then fetch data using `dev.fetch` and upload data using `dev.upload`.  Refer to the code to see how this works.

DAC outputs can be written using `dev.dac(<index>).set(<value>).write` where `<index>` is either 1 or 2 and `<value>` is a value in volts between -1 V and 1 V. 

# Creating the project

To create the project, clone the repository to a directory on your computer, open Vivado, navigate to the fpga/ directory (use `pwd` in the TCL console to determine your current directory and `cd` to navigate, just like in Bash), and then run `source make-project.tcl <project name>` where `<project name>` is the name you want your Vivado project to have.  This should create the project with no errors.  It may not correctly assign the AXI addresses, so you will need to open the address editor and assign the `PS7/AXI_Parse_0/s_axi` interface the address range `0x4000_000` to `0x7fff_ffff`.

