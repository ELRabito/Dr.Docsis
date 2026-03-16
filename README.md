The "Fragmentation-Collapse" Theory
What is it?

The Fragmentation-Collapse is a specific network failure pattern where a broadband connection appears "healthy" during idle times or simple tasks, but fundamentally breaks down the moment it handles real-world data loads.

It occurs when the physical line (Layer 1) is so degraded that it can no longer support the reassembly of fragmented data packets. In DOCSIS (Cable) networks, this is usually caused by Upstream Ingress (external noise leaking into the cable) or failing distribution amplifiers.
Why standard tests fail to detect it

Most speedtests and "ping" monitors use small, non-fragmented packets.

    The "Pulse" Fallacy: A simple Ping is small enough to fit within the standard MTU (Maximum Transmission Unit). It "dodges" the instability, leading the ISP to claim the line is fine.

    The Multi-Stream Bias: Modern speedtests open many parallel connections. If one packet is lost, others keep moving. This hides the fact that the protocol overhead is massive and the signal integrity is actually poor.

How Dr. Docsis proves the defect

This tool uses a "Stress-Logic" that targets the physical weaknesses of the cable infrastructure:

    Forced Fragmentation: By sending UDP packets slightly larger than the standard 1500-byte limit (e.g., 1473 bytes of payload + headers), we force the network stack to split the data.

    The Integrity Trap: If a line has a high Bit Error Rate (BER), there is a statistical certainty that at least one fragment will be corrupted. Because a fragmented packet can only be reassembled if 100% of its parts arrive intact, the entire logical packet is dropped.

    The Single-Stream Drift: We compare a single data stream against ten parallel streams. If the single stream collapses while the multi-stream "brute-forces" its way to the target speed, it is a definitive proof of Signal Jitter and Packet Reordering—both symptoms of a physical hardware defect in the ISP's segment.

The Goal

The goal of this project is to move the conversation with the ISP away from "my internet feels slow" toward "here is the physical proof that your infrastructure cannot handle fragmented traffic due to Layer 1 instability."
