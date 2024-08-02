#!/usr/bin/env bash

# +-------------------------------------------------------------------------+
# | LEMPer CLI - Simple Hardware & Network Benhcmark                        |
# +-------------------------------------------------------------------------+
# | Copyright (c) 2014-2024 MasEDI.Net (https://masedi.net/lemper)          |
# +-------------------------------------------------------------------------+
# | This source file is subject to the GNU General Public License           |
# | that is bundled with this package in the file LICENSE.md.               |
# |                                                                         |
# | If you did not receive a copy of the license and are unable to          |
# | obtain it through the world-wide-web, please send an email              |
# | to license@lemper.cloud so we can send you a copy immediately.          |
# +-------------------------------------------------------------------------+
# | Authors: Edi Septriyanto <me@masedi.net>                                |
# +-------------------------------------------------------------------------+

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

cachefly=$( wget -q -O /dev/null https://cachefly.cachefly.net/100mb.test 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from CacheFly: $cachefly "
ovh=$( wget -q -O /dev/null https://proof.ovh.net/files/100Mb.dat 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from OVH: $ovh "

linodeatl=$( wget -q -O /dev/null http://speedtest.atlanta.linode.com/100MB-atlanta.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Atlanta, GA: $linodeatl "
linodedltx=$( wget -q -O /dev/null http://speedtest.dallas.linode.com/100MB-dallas.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Dallas, TX: $linodedltx "
linodefmt=$( wget -q -O /dev/null http://speedtest.london.linode.com/100MB-london.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Fremont, US: $linodefmt "
linodenj=$( wget -q -O /dev/null http://speedtest.newark.linode.com/100MB-newark.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Newark, NJ: $linodenj "
linodeuk=$( wget -q -O /dev/null http://speedtest.london.linode.com/100MB-london.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, London, UK: $linodeuk "
linodejp=$( wget -q -O /dev/null http://speedtest.tokyo.linode.com/100MB-tokyo.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Tokyo, JP: $linodejp "
linodesgp=$( wget -q -O /dev/null http://speedtest.singapore.linode.com/100MB-singapore.bin 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Linode, Singapore, SGP: $linodesgp "

vodafone=$( wget -q -O /dev/null http://212.183.159.230/100MB.zip 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}' )
echo "Download speed from Vodafone: $vodafone "