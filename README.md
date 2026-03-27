# Dr.Docsis / PROJECT WORK IN PROGRESS

Dr.Docsis is a PowerShell-based utility designed for automated network performance testing and signal diagnostics using iperf3 to identify bottlenecks in DOCSIS cable segments.
* These powershell scripts require iPerf3. Please download it from [iperf.fr](https://iperf.fr/) and place iperf3.exe and cygwin1.dll in the root folder!

    "iPerf3 is a tool for active measurements of the maximum achievable bandwidth on IP networks. It supports tuning of various parameters related to timing, buffers and protocols (TCP, UDP, SCTP with IPv4 and IPv6). For each test it reports the bandwidth, loss, and other parameters."
    
* Then follow the steps in https://github.com/ELRabito/Dr.Docsis/blob/main/TUTORIAL_HOW_TO_USE.ps1

<img src="https://i.imgur.com/9SqAcis.png" alt="Beschreibung" width="1024">

# The "Fragmentation-Collapse" Theory

The Fragmentation-Collapse is a specific network failure pattern where a broadband connection appears "healthy" during idle times or simple tasks, but fundamentally breaks down the moment it handles real-world data loads.

In DOCSIS (Cable) networks, this is usually caused by Upstream Ingress (external noise leaking into the cable), failing distribution amplifiers, or severely overbooked segments.

# Why standard tests fail to detect it
Most speedtests and "ping" monitors use small, non-fragmented packets and aggressive multi-streaming.

* The "Pulse" Fallacy: A simple Ping is small enough to fit within the standard MTU (Maximum Transmission Unit). It "dodges" the instability, leading the ISP to claim the line is fine.
* The Multi-Stream Bias: Modern speedtests open many parallel connections. If one packet is lost, others keep moving. This hides massive protocol overhead and poor signal integrity.
* The L4-Invisibility: Standard tools don't report Retransmissions or TCP Window Scaling. They show you the "arrival speed" but not the "struggle" it took to get there.

# How Dr. Docsis proves the defect

This tool uses a "Stress-Logic" that targets the physical and protocol-level weaknesses of the infrastructure:

# 1. Forced Fragmentation (The Integrity Trap)
By sending UDP packets slightly larger than the standard payload limits (e.g., 1474 bytes + headers), we force the network stack to split data. If a line has a high Bit Error Rate (BER), it is a statistical certainty that at least one fragment will be corrupted. Since a fragmented packet only reassembles if 100% of its parts arrive intact, the entire logical packet is dropped. This reveals "hidden" packet loss that a standard Ping never sees.

# 2. Single-Stream Drift (L2 Instability)

We compare a single data stream (TCP-S) against ten parallel streams (TCP-M). If the single stream collapses while the multi-stream "brute-forces" its way to the target speed, it is definitive proof of Signal Jitter and Packet Reordering—both symptoms of a physical hardware defect in the ISP's segment.

# 3. TCP Window Strangulation (CWND Evidence)

Dr. Docsis tracks the Congestion Window (CWND). A healthy line shows steady window scaling. A defective line shows a "Panic-Sawtooth" pattern:

* The CWND collapses (e.g., down to 6K or 56K) because the TCP stack detects instability and pulls the emergency brake.
* This proves the "slowness" isn't a software issue, but a direct consequence of the transport layer's inability to trust the physical line.

# 4. The Retransmission-Chain (L4 Overhead)

By logging TCP Retransmits, Dr. Docsis exposes how much of your bandwidth is "ghost-traffic." Seeing hundreds of retransmits during a 30-second test proves that the modem is stuck in a loop of re-requesting lost data, making the connection feel "laggy" even if the raw Mbit/s seem high.

# The Goal

The goal of this project is to move the conversation with the ISP away from "my internet feels slow" toward "here is the forensic proof that your infrastructure cannot handle fragmented traffic or maintain TCP window stability due to Layer 1 instability.


