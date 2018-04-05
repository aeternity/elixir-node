curl -fsSL -o libsodium-src.tar.gz "https://github.com/jedisct1/libsodium/releases/download/1.0.16/libsodium-1.0.16.tar.gz"
mkdir libsodium-src
tar -zxf libsodium-src.tar.gz -C libsodium-src --strip-components=1
cd libsodium-src/
sudo ./configure &&  sudo make -j$(nproc) &&  sudo make install && sudo ldconfig
