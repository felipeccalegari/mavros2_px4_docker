FROM ubuntu:22.04
ARG PX4_TAG=v1.16.1
ENV DEBIAN_FRONTEND=noninteractive
ENV PX4_TAG=${PX4_TAG}
SHELL ["/bin/bash", "-lc"]

ARG APT_FLAGS="-o Acquire::Retries=5 --fix-missing"

# --- Base setup ---
RUN apt-get ${APT_FLAGS} update && apt-get ${APT_FLAGS} install -y --no-install-recommends \
    locales curl ca-certificates gnupg lsb-release \
 && locale-gen en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8

# --- ROS 2 Humble repository ---
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
  http://packages.ros.org/ros2/ubuntu jammy main" \
  > /etc/apt/sources.list.d/ros2.list

# --- Core packages ---
RUN apt-get ${APT_FLAGS} update && apt-get ${APT_FLAGS} install -y --no-install-recommends \
    git sudo wget nano vim tmux socat jq lsof iproute2 netcat-openbsd tcpdump \
    python3 python3-pip python3-colcon-common-extensions \
    python3-jinja2 python3-empy python3-toml python3-numpy \
    libfuse2 \
    libxcb-xinerama0 libxkbcommon-x11-0 libxcb-cursor-dev \
    mesa-utils libgl1-mesa-dri libgl1-mesa-glx x11-apps \
 && rm -rf /var/lib/apt/lists/*

RUN apt-get ${APT_FLAGS} update && apt-get ${APT_FLAGS} install -y --no-install-recommends \
    openjdk-21-jdk-headless \
    gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-gl \
 && rm -rf /var/lib/apt/lists/*

RUN apt-get ${APT_FLAGS} update && apt-get ${APT_FLAGS} install -y --no-install-recommends \
    ros-humble-desktop \
    ros-humble-rqt-console ros-humble-rviz2 \
    ros-humble-rosbridge-server ros-humble-rosbridge-suite \
    ros-humble-mavros ros-humble-mavros-extras \
 && rm -rf /var/lib/apt/lists/*

RUN apt-get purge -y modemmanager || true \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

# --- MAVROS GeographicLib datasets ---
RUN /opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh \
 && echo "GeographicLib datasets installed" \
 || echo "WARNING: GeographicLib installation failed"

# --- PX4 dependencies ---
RUN apt-get ${APT_FLAGS} update && apt-get ${APT_FLAGS} install -y --no-install-recommends \
    build-essential cmake ninja-build \
    pkg-config libxml2-utils \
 && rm -rf /var/lib/apt/lists/*

# --- Clone PX4-Autopilot seed ---
RUN git clone https://github.com/PX4/PX4-Autopilot.git /opt/PX4-Autopilot-seed \
 && cd /opt/PX4-Autopilot-seed \
 && git checkout ${PX4_TAG} \
 && git submodule update --init --recursive

# --- PX4 setup ---
RUN cd /opt/PX4-Autopilot-seed \
 && bash ./Tools/setup/ubuntu.sh --no-nuttx \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# --- DISABLE PX4 SAFETY CHECKS (Persistent) ---
# Create custom rcS startup file that disables all safety checks
RUN cat > /opt/PX4-Autopilot-seed/ROMFS/px4fmu_common/init.d-posix/rcS.append << 'EOF'
# Disable safety checks for development
param set COM_ARM_WO_GPS 1
param set CBRK_IO_SAFETY 22027
param set NAV_RCL_ACT 0
param set NAV_DLL_ACT 0
param set CBRK_FLIGHTTERM 121212
param set CBRK_SUPPLY_CHK 894281
param set CBRK_USB_CHK 197848
param set EKF2_REQ_EPH 1000
param set EKF2_REQ_EPV 1000

# Extra onboard MAVLink endpoint for the /dev/ttyV1 socat bridge
mavlink start -u 14560 -o 14561 -t 127.0.0.1 -m onboard -r 40000
EOF

# Append custom params to the main startup script
RUN cd /opt/PX4-Autopilot-seed && \
    echo "" >> ROMFS/px4fmu_common/init.d-posix/rcS && \
    echo "# Load custom safety bypass settings" >> ROMFS/px4fmu_common/init.d-posix/rcS && \
    cat ROMFS/px4fmu_common/init.d-posix/rcS.append >> ROMFS/px4fmu_common/init.d-posix/rcS

# --- Setup bashrc ---
RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc

RUN mkdir -p /opt/PX4-Autopilot /root/Agents

COPY container-startup.sh /usr/local/bin/container-startup.sh
RUN chmod +x /usr/local/bin/container-startup.sh

# --- QGroundControl ---
RUN useradd -m -s /bin/bash qgc \
 && usermod -aG dialout qgc \
 && mkdir -p /home/qgc \
 && wget -O /home/qgc/QGroundControl.AppImage \
    https://d176tv9ibo4jno.cloudfront.net/latest/QGroundControl-x86_64.AppImage \
 && chmod +x /home/qgc/QGroundControl.AppImage \
 && cd /home/qgc \
 && /home/qgc/QGroundControl.AppImage --appimage-extract \
 && chown -R qgc:qgc /home/qgc

RUN cat > /usr/local/bin/qgc << 'EOF'
#!/usr/bin/env bash
set -e

DISPLAY_VALUE="${DISPLAY:-:0}"
ROOT_XAUTH="${XAUTHORITY:-/root/.Xauthority}"
QGC_XAUTH="/home/qgc/.Xauthority"

if [ -f "${ROOT_XAUTH}" ]; then
  cp "${ROOT_XAUTH}" "${QGC_XAUTH}" 2>/dev/null || true
  chown qgc:qgc "${QGC_XAUTH}" 2>/dev/null || true
fi

exec runuser -u qgc -- env \
  DISPLAY="${DISPLAY_VALUE}" \
  XAUTHORITY="${QGC_XAUTH}" \
  /home/qgc/squashfs-root/AppRun
EOF
RUN chmod +x /usr/local/bin/qgc

# --- Set working directory ---
WORKDIR /opt/PX4-Autopilot
