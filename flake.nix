{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let

    pkgs = import nixpkgs { system = "x86_64-linux"; };
    devkitarm-img = pkgs.dockerTools.pullImage {
      imageName = "devkitpro/devkitarm";
      imageDigest = "sha256:2ee5e6ecdc768aa7fb8f2e37be2e27ce33299e081caac20a0a2675cdc791cf32";
      sha256 = "sha256-KUiKhA3QhMR9cIQC82FI0AgE+Ud7dAXY50xSn5oWZzI=";
      finalImageName = "devkitpro/devkitarm";
      finalImageTag = "20240202";
    };

    libctrpf-img = pkgs.dockerTools.pullImage {
      imageName = "pablomk7/libctrpf";
      imageDigest = "sha256:710dd1dede64b599423cae413f2da88a00433578949467ea5680f572525481c2";
      sha256 = "sha256-z3qvI9dTG3HzI6HYPzLmLOq1ISh5XxSMnlL81qZCMTs=";
      finalImageName = "pablomk7/libctrpf";
      finalImageTag = "0.7.4";
    };

    extractDocker = image: dir:
      pkgs.vmTools.runInLinuxVM (
        pkgs.runCommand "docker-preload-image" {
          memSize = 8 * 1024;
          buildInputs = with pkgs; [
            curl
            kmod
            docker
            e2fsprogs
            utillinux
          ];
        }
        ''
          modprobe overlay

          # from https://github.com/tianon/cgroupfs-mount/blob/master/cgroupfs-mount
          mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup
          cd /sys/fs/cgroup
          for sys in $(awk '!/^#/ { if ($4 == 1) print $1 }' /proc/cgroups); do
            mkdir -p $sys
            if ! mountpoint -q $sys; then
              if ! mount -n -t cgroup -o $sys cgroup $sys; then
                rmdir $sys || true
              fi
            fi
          done

          dockerd -H tcp://127.0.0.1:5555 -H unix:///var/run/docker.sock &

          until $(curl --output /dev/null --silent --connect-timeout 2 http://127.0.0.1:5555); do
            printf '.'
            sleep 1
          done

          echo load image
          docker load -i ${image}

          echo run image
          docker run ${image.destNameTag} tar -C '${toString dir}' -c . | tar -xv --no-same-owner -C $out || true

          echo end
          kill %1
        ''
      );
  in {

    packages.x86_64-linux.devkitARM = pkgs.stdenv.mkDerivation {
      name = "devkitARM";
      src = extractDocker devkitarm-img "/opt/devkitpro";
      nativeBuildInputs = [pkgs.autoPatchelfHook];
      buildInputs = with pkgs; [
        stdenv.cc.cc
        ncurses6
        zsnes
      ];
      buildPhase = "true";
      installPhase = ''
        mkdir -p $out
        cp -r $src/{devkitARM,libgba,libnds,libctru,libmirko,liborcus,portlibs,tools} $out
        rm -rf $out/pacman
      '';
    };

    packages.x86_64-linux.libctrpf = pkgs.stdenv.mkDerivation {
      name = "libctrpf";
      src = extractDocker libctrpf-img "/opt/devkitpro";
      nativeBuildInputs = [ pkgs.autoPatchelfHook ];
      buildInputs = with pkgs; [
        stdenv.cc.cc
      ];
      buildPhase = "true";
      installPhase = ''
        mkdir -p $out
        cp -r $src/{libctrpf,tools} $out
        rm -rf $out/pacman
      '';
    };
  };
}
