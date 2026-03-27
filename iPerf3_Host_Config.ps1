# Used hosts with port/port-range
# Server List https://iperf3serverlist.net/
$targets = @(

	@{ Country = "Germany";         Host = "fra.speedtest.clouvider.net";    Ports = 5200..5209 }
    @{ Country = "Germany";         Host = "speedtest.wtnet.de";             Ports = 5200..5209 }
    @{ Country = "Switzerland";     Host = "t5.cscs.ch";                     Ports = 5201..5203 }
    @{ Country = "Switzerland";     Host = "speedtest.iway.ch";              Ports = 5201 }
    @{ Country = "Switzerland";     Host = "speedtest.shinternet.ch";        Ports = 5200..5209 }
	@{ Country = "Switzerland";     Host = "speedtest.init7.net";        	 Ports = 5201..5204 }
    @{ Country = "France";          Host = "ping.online.net";                Ports = 5200..5209 }
	@{ Country = "France";          Host = "ping-90ms.online.net";           Ports = 5200..5209 }
	@{ Country = "Netherlands";     Host = "iperf-ams-nl.eranium.net";       Ports = 5201..5210 }
    @{ Country = "Denmark";         Host = "speed1.fiberby.dk";              Ports = 9201..9240 }
    @{ Country = "Denmark";         Host = "speed2.fiberby.dk";              Ports = 9201..9240 }
    @{ Country = "Norway";          Host = "lg.gigahost.no";                 Ports = 9201..9240 }
)
