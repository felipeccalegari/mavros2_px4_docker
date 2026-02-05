FROM ubuntu:22.04
ARG PX4_TAG=v1.16.1
ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-lc"]

# --- Base setup ---
RUN apt-get update && apt-get install -y --no-install-recommends \
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
RUN apt-get update && apt-get install -y --no-install-recommends \
    git sudo wget \
    openjdk-21-jre-headless \
    ros-humble-desktop \
    ros-humble-mavros ros-humble-mavros-extras \
    ros-humble-rosbridge-server ros-humble-rosbridge-suite \
    ros-humble-rqt-console ros-humble-rviz2 \
    python3 python3-pip python3-colcon-common-extensions \
    python3-jinja2 python3-empy python3-toml python3-numpy \
    mesa-utils libgl1-mesa-dri libgl1-mesa-glx x11-apps \
 && rm -rf /var/lib/apt/lists/*

# --- MAVROS GeographicLib datasets ---
RUN /opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh \
 && echo "GeographicLib datasets installed" \
 || echo "WARNING: GeographicLib installation failed"

# --- PX4 dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build \
    pkg-config libxml2-utils \
 && rm -rf /var/lib/apt/lists/*

# --- Clone PX4-Autopilot ---
RUN git clone https://github.com/PX4/PX4-Autopilot.git /opt/PX4-Autopilot \
 && cd /opt/PX4-Autopilot \
 && git checkout ${PX4_TAG} \
 && git submodule update --init --recursive

# --- PX4 setup ---
RUN cd /opt/PX4-Autopilot \
 && bash ./Tools/setup/ubuntu.sh --no-nuttx \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# --- DISABLE PX4 SAFETY CHECKS (Persistent) ---
# Create custom rcS startup file that disables all safety checks
RUN cat > /opt/PX4-Autopilot/ROMFS/px4fmu_common/init.d-posix/rcS.append << 'EOF'
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
EOF

# Append custom params to the main startup script
RUN cd /opt/PX4-Autopilot && \
    echo "" >> ROMFS/px4fmu_common/init.d-posix/rcS && \
    echo "# Load custom safety bypass settings" >> ROMFS/px4fmu_common/init.d-posix/rcS && \
    cat ROMFS/px4fmu_common/init.d-posix/rcS.append >> ROMFS/px4fmu_common/init.d-posix/rcS

# --- Setup bashrc with helpful aliases ---
RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc && \
    echo "alias px4='cd /opt/PX4-Autopilot'" >> /root/.bashrc && \
    echo "alias startpx4='make px4_sitl gz_x500'" >> /root/.bashrc && \
    echo "alias arm='ros2 service call /mavros/cmd/arming mavros_msgs/srv/CommandBool \"{value: true}\"'" >> /root/.bashrc && \
    echo "alias disarm='ros2 service call /mavros/cmd/arming mavros_msgs/srv/CommandBool \"{value: false}\"'" >> /root/.bashrc && \
    echo "alias status='ros2 topic echo /mavros/state --once'" >> /root/.bashrc

# --- Set working directory ---
WORKDIR /opt/PX4-Autopilot