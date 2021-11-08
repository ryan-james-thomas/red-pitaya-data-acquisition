import subprocess
import struct

MEM_ADDR = 0x40000000

def write(data,header):
    response = {"err":False,"errMsg":"","data":b''}

    if ("debug" in header) and (header["debug"]):
        response["errMsg"] = "Message received"
        return response       
    elif header["mode"] == "write":
        for i in range(0,len(data),2):
            addr = MEM_ADDR + data[i]
            cmd = ['monitor',format(addr),'0x' + '{:0>8x}'.format(data[i+1])]
            if ("print" in header) and (header["print"]):
                print("Command: ",cmd)
            result = subprocess.run(cmd,stdout=subprocess.PIPE)
            if result.returncode != 0:
                break
            else:
                data = result.stdout.decode('ascii').rstrip()
                if len(data) > 0:
                    buf = struct.pack("<I",int(data,16))
                else:
                    buf = b''
                response["data"] += buf

    elif header["mode"] == "read":
        for i in range(0,len(data)):
            addr = MEM_ADDR + data[i]
            cmd = ['monitor',format(addr)]
            if ("print" in header) and (header["print"]):
                print("Command: ",cmd)
            result = subprocess.run(cmd,stdout=subprocess.PIPE)
            if result.returncode != 0:
                break
            else:
                data = result.stdout.decode('ascii').rstrip()
                buf = struct.pack("<I",int(data,16))
                response["data"] += buf

    elif header["mode"] == "fetch ram":
        cmd = ['./fetchRAM',format(header["numSamples"])]
        if ("print" in header) and (header["print"]):
            print("Command: ",cmd)
        result = subprocess.run(cmd,stdout=subprocess.PIPE)

        if result.returncode == 0:
            fid = open("SavedData.bin","rb")
            response["data"] = fid.read()
            fid.close()

    elif header["mode"] == "fetch iq":
        cmd = ['./fetchIQ',format(header["numSamples"])]
        if ("print" in header) and (header["print"]):
            print("Command: ",cmd)
        result = subprocess.run(cmd,stdout=subprocess.PIPE)

        if result.returncode == 0:
            fid = open("SavedData.bin","rb")
            response["data"] = fid.read()
            fid.close()

    elif header["mode"] == "fetch fifo":
        cmd = ['./fetchFIFO','-t',format(header["saveType"]),'-n',format(header["numSamples"])]

        if ("print" in header) and (header["print"]):
            print("Command: ",cmd)
        result = subprocess.run(cmd,stdout=subprocess.PIPE)

        if result.returncode == 0:
            fid = open("SavedData.bin","rb")
            response["data"] = fid.read()
            fid.close()
    
    
    if result.returncode != 0:
        response = {"err":True,"errMsg":"Bus error","data":b''}

    return response
        