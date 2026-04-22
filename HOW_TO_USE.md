# Powershell iperf3 stress test 

Used hosts in this tests with port/port-range
Server List https://iperf3serverlist.net/

    "Germany";         Host = "fra.speedtest.clouvider.net";    Ports = 5200..5209 }
    "Germany";         Host = "speedtest.wtnet.de";             Ports = 5200..5209 }
    "Switzerland";     Host = "t5.cscs.ch";                     Ports = 5201..5203 }
    "Switzerland";     Host = "speedtest.iway.ch";              Ports = 5201 }
    "Switzerland";     Host = "speedtest.shinternet.ch";        Ports = 5200..5209 }
    "France";          Host = "ping.online.net";                Ports = 5200..5209 }
    "Netherlands";     Host = "iperf-ams-nl.eranium.net";       Ports = 5201..5210 }
    "Netherlands";     Host = "speedtest.ams1.novogara.net";    Ports = 5200..5209 }
    "Denmark";         Host = "speed1.fiberby.dk";              Ports = 9201..9240 }
    "Denmark";         Host = "speed2.fiberby.dk";              Ports = 9201..9240 }
    "Norway";          Host = "lg.gigahost.no";                 Ports = 9201..9240 }

# 1 - First Step allow script execution in the powershell window

    Set-ExecutionPolicy RemoteSigned -Scope Process

# 2 - Execute the DrDocsis_Test.ps1 

    Parameters UPLOAD DOWNLOAD CONTRACT_MINIMUM (eg. 100mbit 50mbit 90% Legal Minimum)
    .\DrDocsis_Test.ps1 100 50 90

# 3 - Execute the DrDocsis_Analyze.ps1 in a second powershell window (Also allow script execution with the prompt from the start).

# Standard-Check: (Scans Logs_Current folder).

    .\DrDocsis_Analyze.ps1 

Parameter UPLOAD DOWNLOAD CONTRACT_MINIMUM (eg. 100mbit 50mbit 90% Legal Minimum)

    .\DrDocsis_Analyze.ps1 100 50 90

# Archive-Scan: (Scans Logs_History folder).

    .\DrDocsis_Analyze.ps1 100 50 90 -History 

# Scan & Archive: (Scans current logs and moves them to Logs_History folder).

    .\DrDocsis_Analyze.ps1 100 50 90 -Archive 

# Detects FEC problems due to ingress or segment congestion (over load).

    .\DrDocsis_Breakpoint.ps1


# 5 - Manual replication of the automated scripts to verify authenticity

Initial idea to prove the problem automatically
UDP because no retransmission, also forced fragmentation of the package to get over standard MTU.

# FEC Collapse UDP UPLOAD replication
    .\iperf3.exe -c speedtest.iway.ch -p 5201 -u -b 40M -l 1473 -t 20

    .\iperf3.exe -c speedtest.iway.ch -p 5201 -u -b 30M -l 1473 -t 20 

    .\iperf3.exe -c speedtest.iway.ch -p 5201 -u -b 13M -l 1473 -t 20 


# FEC Collape UDP Download 
    .\iperf3.exe -c speedtest.iway.ch -p 5201 -u -b 40M -l 1473 -t 20 -R

    .\iperf3.exe -c speedtest.iway.ch -p 5201 -u -b 30M -l 1473 -t 20 -R

    .\iperf3.exe -c speedtest.iway.ch -p 5201 -u -b 13M -l 1473 -t 20 -R
