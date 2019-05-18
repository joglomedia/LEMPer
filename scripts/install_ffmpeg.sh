# Install FFMPEG
# http://trac.ffmpeg.org/wiki/CompilationGuide/Ubuntu

sudo apt-get update
sudo apt-get -y install autoconf automake build-essential libass-dev libfreetype6-dev libgpac-dev \
  libsdl1.2-dev libtheora-dev libtool libva-dev libvdpau-dev libvorbis-dev libx11-dev \
  libxext-dev libxfixes-dev pkg-config texi2html zlib1g-dev
mkdir ~/ffmpeg_sources

# Yasm
#sudo apt-get install yasm
cd ~/ffmpeg_sources
wget http://www.tortall.net/projects/yasm/releases/yasm-1.2.0.tar.gz
tar xzvf yasm-1.2.0.tar.gz
cd yasm-1.2.0
./configure --prefix="$HOME/ffmpeg_build" --bindir="/usr/local/bin"
make
make install
make distclean
export "PATH=$PATH:/usr/local/bin"

# libx264 - H.264 video encoder
cd ~/ffmpeg_sources
wget http://download.videolan.org/pub/x264/snapshots/last_x264.tar.bz2
tar xjvf last_x264.tar.bz2
cd x264-snapshot*
./configure --prefix="$HOME/ffmpeg_build" --bindir="/usr/local/bin" --enable-static
make
make install
make distclean

# libfdk-aac - AAC audio encoder
cd ~/ffmpeg_sources
wget -O fdk-aac.zip https://github.com/mstorsjo/fdk-aac/zipball/master
unzip -qq fdk-aac.zip
cd mstorsjo-fdk-aac*
autoreconf -fiv
./configure --prefix="$HOME/ffmpeg_build" --disable-shared
make
make install
make distclean

# libmp3lame - MP3 audio encoder
#sudo apt-get install libmp3lame-dev
sudo apt-get install nasm
cd ~/ffmpeg_sources
wget http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz
tar xzvf lame-3.99.5.tar.gz
cd lame-3.99.5
./configure --prefix="$HOME/ffmpeg_build" --enable-nasm --disable-shared
make
make install
make distclean

# libopus - Opus audio decoder and encoder
#sudo apt-get install libopus-dev
cd ~/ffmpeg_sources
wget http://downloads.xiph.org/releases/opus/opus-1.1.tar.gz
tar xzvf opus-1.1.tar.gz
cd opus-1.1
./configure --prefix="$HOME/ffmpeg_build" --disable-shared
make
make install
make distclean

# libvpx - VP8/VP9 video encoder and decoder
cd ~/ffmpeg_sources
wget http://webm.googlecode.com/files/libvpx-v1.3.0.tar.bz2
tar xjvf libvpx-v1.3.0.tar.bz2
cd libvpx-v1.3.0
./configure --prefix="$HOME/ffmpeg_build" --disable-examples
make
make install
make clean

# ffmpeg
cd ~/ffmpeg_sources
#wget http://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2
#tar xjvf ffmpeg-snapshot.tar.bz2
git clone git://source.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg
PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig"
export PKG_CONFIG_PATH
./configure --prefix="$HOME/ffmpeg_build" --extra-cflags="-I$HOME/ffmpeg_build/include" \
   --extra-ldflags="-L$HOME/ffmpeg_build/lib" --bindir="/usr/local/bin" --extra-libs="-ldl" --enable-gpl \
   --enable-libass --enable-libfdk-aac --enable-libfreetype --enable-libmp3lame --enable-libopus \
   --enable-libtheora --enable-libvorbis --enable-libvpx --enable-libx264 --enable-nonfree --enable-x11grab
make
make install
make distclean
hash -r

# Updating ffmpeg
#rm -rf ~/ffmpeg_build ~/ffmpeg_sources ~/bin/{ffmpeg,ffprobe,ffserver,vsyasm,x264,yasm,ytasm}

# Reverting Changes Made by This Guide
#rm -rf ~/ffmpeg_build ~/ffmpeg_sources ~/bin/{ffmpeg,ffprobe,ffserver,vsyasm,x264,yasm,ytasm}
#sudo apt-get autoremove autoconf automake build-essential libass-dev libfreetype6-dev libgpac-dev \
#  libmp3lame-dev libopus-dev libsdl1.2-dev libtheora-dev libtool libva-dev libvdpau-dev \
#  libvorbis-dev libvpx-dev libx11-dev libxext-dev libxfixes-dev texi2html zlib1g-dev
#sed -i '/ffmpeg_build/c\' ~/.manpath
#hash -r
