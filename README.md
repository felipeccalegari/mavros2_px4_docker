**Custom Docker image for PX4 1.16 + MAVROS2 Humble.**

This project consists of a Docker image and container that integrates PX4 1.16.1 + ROS 2 Humble alongside Jason BDI Agent to connect via Mavros or Mavlink.

Steps to run this project (based on an Ubuntu distribution on the local machine):

1) Clone this project
```
mkdir mavros_px4
cd mavros_px4
git clone https://github.com/felipeccalegari/mavros2_px4_docker.git
```

2) Build the Docker image:

```
cd mavros2_px4_docker
docker compose build --no-cache
```
*It's normal to take a while to build.*

3) Choose one GUI mode and start the container:

**Option A** - noVNC in the browser (only recommended if the user cannot use *xhost* due to processing limitations):
```
docker compose -f docker-compose_novnc.yaml up -d
```
Then open:
```
http://localhost:8080/vnc.html
```
and click `Connect`.

**Option B** - host X11 via `xhost`:
```
xhost +local:docker
docker compose -f docker-compose_xhost.yaml up -d
```

If you want to switch from one mode to the other, stop the current stack first:
```
docker compose -f docker-compose_novnc.yaml stop
docker compose -f docker-compose_xhost.yaml stop
```

Both options start the container in the background (detached mode).

- Execute container commands:
```
docker exec -it px4_ros2 bash
```
This will open the container's default directory (*/opt/PX4-Autopilot*)

- Execute the simulation:
```
make px4_sitl gz_x500
```
This will launch the default vehicle for the PX4 simulation (SITL) in Gazebo simulator.

*For more options/vehicles, I recommend checking out PX4's official documentation for the right command.*

- The file `px4_mavlink_mavros_mapping.xlsx` has been generated (via OpenAI's Codex with version GPT 5.4) to be used as reference to map most Mavros and Mavlink commands/messages available in the current system.

4) Jason Agent code in the /Agents/ folder:

To run Mavros examples:
```
cd Agents/Mavros
chmod +x gradlew
./gradlew run
```
*There are different missions/intentions in the agent .asl file, to run a specific scenario simply uncomment the desired intentions to run.*

The Docker container system also automatically clone's a Mavlink extension into `Agents/Mavlink` directory, which allows the user to run pure Mavlink (v2) commands using the same framework as base - [Embedded-Mas](https://github.com/embedded-mas/embedded-mas).
Mavlink usually requests Serial or UDP connection to work, for this case it has been added a "virtual serial" port into the system that is running in the background as a process via *socat* and has already been set up in PX4's startup script.

To run the Mavlink agents:

```
cd Agents/Mavlink/examples/jacamo/serial_device/perception_action
./gradlew run
```
*Similar to the Mavros example, the Mavlink scenario also contains in the same file multiple commented examples. To run a specific mission, uncomment the specific code block.*

**Extras:**
- For volume persistence we have a few options available:
1) `./Agents:/root/Agents`: maps Agents directory inside container to your local Agents directory.
2) `./PX4-Autopilot:/opt/PX4-Autopilot`: allows the user to edit PX4 files if desired (for example if they wish to create custom scenarios).

- Some great tools have also being added into the image such as: QGroundControl (simply running `qgc` command should launch it) for flight control monitoring, RQT Console to debug ROS/Mavros messages (run with `ros2 run rqt_console rqt_console` command), nano and vim for text editor, socat and others.
