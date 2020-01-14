#!/bin/bash

# Hardware benchmark.
echo "### Hardware Informations ###"

cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo )
echo "CPU model: $cname"
cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
echo "CPU cores: $cores"
freq=$( awk -F: ' /cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo )
echo "CPU frequency: $freq MHz"
tram=$( free -m | awk '/^Mem:/ { print $2 }' )
echo "Total RAM size: $tram MB"
swap=$( free -m | awk '/^Swap:/ { print $2 }' )
echo "Total Swap size: $swap MB"
up=$(uptime|awk '{ $1=$2=$(NF-6)=$(NF-5)=$(NF-4)=$(NF-3)=$(NF-2)=$(NF-1)=$NF=""; print }')
echo "System uptime: $up"
load=$(uptime | awk -F:  '{ print $5 }')
echo "Load average: $load"
echo ""

# Disk I/O benchmark.
echo "### Disk I/O Benchmark ###"
io=$( ( dd if=/dev/zero of=test_$$ bs=64k count=16k conv=fdatasync && rm -f test_$$ ) 2>&1 | awk -F, '{io=$NF} END { print io}' )
echo "I/O speed: $io"

echo ""

# Network speed test benchmark.
echo "### Network Speedtest Benchmark ###"

cachefly=$( wget -O /dev/null http://cachefly.cachefly.net/100mb.test 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from CacheFly: $cachefly "
leaseweb=$( wget -O /dev/null http://mirror.leaseweb.com/speedtest/100mb.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Leaseweb, Haarlem, NL: $leaseweb "

linodeatl=$( wget -O /dev/null http://speedtest.atlanta.linode.com/100MB-atlanta.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Atlanta, GA: $linodeatl "
linodedltx=$( wget -O /dev/null http://speedtest.dallas.linode.com/100MB-dallas.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Dallas, TX: $linodedltx "
linodefmt=$( wget -O /dev/null http://speedtest.london.linode.com/100MB-london.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Fremont, US: $linodefmt "
linodenj=$( wget -O /dev/null http://speedtest.newark.linode.com/100MB-newark.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Newark, NJ: $linodenj "
linodeuk=$( wget -O /dev/null http://speedtest.london.linode.com/100MB-london.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, London, UK: $linodeuk "
linodejp=$( wget -O /dev/null http://speedtest.tokyo.linode.com/100MB-tokyo.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Tokyo, JP: $linodejp "
linodesgp=$( wget -O /dev/null http://speedtest.singapore.linode.com/100MB-singapore.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Singapore, SGP: $linodesgp "

slsea=$( wget -O /dev/null http://speedtest.sea01.softlayer.com/downloads/test100.zip 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Softlayer, Seattle, WA: $slsea "
slsjc=$( wget -O /dev/null http://speedtest.sjc01.softlayer.com/downloads/test100.zip 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Softlayer, San Jose, CA: $slsjc "
sldal=$( wget -O /dev/null http://speedtest.dal05.softlayer.com/downloads/test100.zip 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Softlayer, Dallas, TX: $sldal "
slwdc=$( wget -O /dev/null http://speedtest.wdc01.softlayer.com/downloads/test100.zip 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Softlayer, Washington, DC: $slwdc "
slsng=$( wget -O /dev/null http://speedtest.sng01.softlayer.com/downloads/test100.zip 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Softlayer, Singapore: $slsng "
