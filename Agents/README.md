# BDI Jason Agents

This directory contains [Jason's](https://jason-lang.github.io/) BDI projects to run via Mavros/Mavlink (although Mavlink example isn't present in this repository, it'll be automatically downloaded when the Docker Container is created).

Both use the same [Embedded-Mas](https://github.com/embedded-mas/embedded-mas) framework as base to run. Embedded-Mas is a framework that allows Jason agents to integrate with embedded systems via ROS or serial connection.

In both Mavros/Mavlink directories, the user may find a `benchmark_mavros.sh` (on the /Mavros folder) or `benchmark_mavlink.sh` (/Mavlink folder). They're meant to test CPU and RAM memory consumption in %. If the user wishes to run either, they must first allow it's execution by `chmod +x ./benchmark_X.sh` and then run with `./benchmark_X.sh` (assuming they're already in the desired directory).

To run either Mavros or Mavlink's agent, the user must run the following commands:
```
cd Agents/Mavros #or Agents/Mavlink
./gradlew run
```


## Mavros Agents
[Mavros](https://wiki.ros.org/mavros) is an extendable communication node for ROS that allows autopilots to communicate using [Mavlink](https://mavlink.io/en/) via ROS systems (topics and services).

The main .asl Agent code and it's .yaml configuration can be found in `Agents/Mavros/src/agt/`. 

The file with .yaml extension is used to define main ROS connections, alongside it's default classes, agent's perceptions (topic) and actions (service or topic). It's recommendeded to read instructions found in the .yaml file and in the original repository from Embedded-Mas so the user can properly understand what to define in there.

There's also defined in the *Device* bracket a Java class called "CustomClass" (`Agents/Mavros/src/java/CustomClass.java`), which has been created to work with special data types that currently are not supported by Embedded-Mas framework for custom internal actions. If this internal action is defined in the CustomClass, we don't need to define it in .yaml file.

### Examples:
In the agent .asl file (`Agents/Mavros/src/agt/sample_agent.asl`), we have the agent code itself. As mentioned, it is consisted of multiple examples that the user can uncomment and try it out for themselves:

- **Takeoff** - basic arm/takeoff to default height.
- **Mission Mode** - uses "AUTO.MISSION" mode from PX4 where the UAV would fly to the specific coordinates (Lat and Lon in degrees, Alt in meters).
- **Battery monitoring** (used alongside Mission Mode) - agent percepts the battery information from PX4 and acts depending on it's percentage left.
- **Reposition** "counter" - when not in mission, Mavlink/Mavros uses REPOSITION mode for the UAV flies to specific coordinates. This example works as a counter: agent sends first coordinate (with altitude Z=1), then it'll perceive the UAV current coordinates and if the drone reaches that altitude Z (or if it's within a 0.35m range), it'll add that Z parameter in 1 unit and send this new coordinate as action and so on, until the UAV reaches Z=10.
- **Set parameter** "counter" - this example also works as a counter but its purpose is to compare with Mavlink to measure which mechanism is faster. It sends an initial velocity of 1 to the "MPC_Z_VEL_MAX_UP" parameter (in short words, a parameter that determines maximum vertical velocity) and then a plan will perceive this information and once the agent percepts that the parameter is at the desired value, it'll react and increase in 1 unit this parameter, and so on until it reaches 100. Since the goal is to test latencies only, this example *alone* doesn't have *physical* impact in the simulation since the vehicle is on the ground, not moving.
- **Offboard Mode** - uses "OFFBOARD" mode from PX4 where user can fly to a specific coordinate (X,Y,Z) with that mode but the user must follow standard procedures for that (data must be sent with the minimum of 2Hz, for example). Originally, the command for this requires other parameters as well but they been covered under the .java classes, so the user only need to worry about the respective "Forward, Right, Up" coordinates. Also, these coordinates are the relative position given the drone's current location, not relative to where the drone took off from. For example, if, after the drone took off, the user desires to send the UAV to 2m forward, then simply send (2, 0, 0), and then afterwards go 3 units left simply send (0, -3, 0).

## Mavlink Agents
Mavlink is a lightweight messaging protocol for communicating with drones. The messages are defined in a standard .xml file (autopilots usually follow the official [common.xml](https://mavlink.io/en/messages/common.html)).

Natively, the Embedded-Mas didn't have support to send Mavlink messages through serial connection. Therefore, an extension class called *"Mavlink4EmbeddedMas* was created in which extends the usual serial write/read properties from *NRJ4EmbeddedMas* class (present in the Embedded-Mas framework). This new class manages Mavlink's connection, decode/encode Mavlink's messages and helps with populating non-high level standard parameters so the agent developer only needs to worry about standard parameters from the specific message. This was possible using [DroneFleet](https://github.com/dronefleet/mavlink) library for Java, that even though it no longer receives updates/maintenance, it still works well with Embedded-Mas.
*Note: it's not 100% guaranteed that a specific Mavlink command/message will work with the system, however, as long as it's supported by the library's MavCmd class, it should work.*

The main .asl Agent code and it's .yaml configuration can be found in `Agents/Mavlink/examples/jacamo/serial_device/perception_action/src/agt` (assuming the user has already built the Docker image locally and intiated the Docker Container). 

The .yaml configuration file is where we define the serial connection and the agent's actions. In **serialActions**, we define the agent's custom action name (*actionName*) and the standard Mavlink name (*actuationName*).

*Note 1: In the current version of Embedded-Mas for serial connection, it's not supported to define perceptions in this file.*

*Note 2: For this specific system, it's recommended to leave the "serial" and "baudrate" definitions as they are, since they're based on the system's internal connection with Socat (used to establish a virtual serial connection), PX4 and Gradle (build.gradle) mapping.*

### Examples:
In the agent .asl file (`Agents/Mavlink/examples/jacamo/serial_device/perception_action/src/agt/sample_agent.asl`), we have the agent code itself. It is consisted of multiple examples that the user can uncomment and try it out for themselves:

- **Reposition counter**: like Mavros example, when not in mission, Mavlink uses REPOSITION mode for the UAV flies to specific coordinates. This example works as a counter: agent sends first coordinate (with altitude Z=1), then it'll perceive the UAV current coordinates and if the drone reaches that altitude Z (or if it's within a 0.35m range), it'll add that Z parameter in 1 unit and send this new coordinate as action and so on, until the UAV reaches Z=10.

- **Takeoff and Land**: Simple takeoff/land example.

- **Takeoff and Return to Launch (RTL)**: Takeoff and RTL (origin) example.

- **Reposition and Land**: uses Reposition command to send the drone to specific coordinates and then land.

- **Mission mode**: uses mission mode to go to different coordinates. It's necessary to use extra action *.mission_start(_,_)* stating initial mission (0 - 1st) and last (if -1, system recognizes as last waypoint added).

- **Parameter counter**: this example also works as a counter but its purpose is to compare with Mavros to measure which mechanism is faster. It sends an initial velocity of 1 to the "MPC_Z_VEL_MAX_UP" parameter (in short words, a parameter that determines maximum vertical velocity) and then a plan will perceive this information and once the agent percepts that the parameter is at the desired value, it'll react and increase in 1 unit this parameter, and so on until it reaches 100. Since the goal is to test latencies only, this example *alone* doesn't have *physical* impact in the simulation since the vehicle is on the ground, not moving.

- **Offboard Mode** - uses "OFFBOARD" mode from PX4 where user can fly to a specific coordinate (X,Y,Z) with that mode but the user must follow standard procedures for that (data must be sent with the minimum of 2Hz, for example). Originally, the command for this requires other parameters as well but they been covered under the .java classes, so the user only need to worry about the respective "Forward, Right, Up" coordinates. Also, these coordinates are the relative position given the drone's current location, not relative to where the drone took off from. For example, if, after the drone took off, the user desires to send the UAV to 2m forward, then simply send (2, 0, 0), and then afterwards go 3 units left simply send (0, -3, 0).

#### Perceptions Examples:

On this Mavlink extension, the data telemetry coming from the flight controller (PX4, for example) are the agent's perceptions of the environment. The perception name is derived from the Mavlink mesage type by removing `_` symbol, joining words and then converting the result to lowercase. To illustrate, the table below compares the telemetry and how it is used in Jason code:

| MAVLink message | Jason perception |
| --- | --- |
| `HEARTBEAT` | `heartbeat(...)` |
| `GLOBAL_POSITION_INT` | `globalpositionint(...)` |
| `LOCAL_POSITION_NED` | `localpositionned(...)` |
| `ATTITUDE` | `attitude(...)` |
| `SYS_STATUS` | `sysstatus(...)` |
| `STATUSTEXT` | `statustext(...)` |

To avoid high-rate telemetry data being spammed in Jason's belief system and messages not being properly processed/converted, it was added some time gaps before printing or reacting to the perceptions.

- **Heartbeat**: information about the flight controller.

- **Local Position NED**: local position in NED (North-East-Down) coordinates.

- **Attitude**: vehicle orientation.

- **System Status**: status about the system.

- **Status Text**: Text regarding system status and its severity.

- **Global Position INT**: GPS information in Lat, Lon, Alt, RelAlt format (Lat and Lon are in degrees x 1e7, Alt and RelAlt are in millimeters).

- **Battery**: information about battery percentage, voltage and current.
    - Note: the battery perception has been customized in the Mavlink class to "force" PX4 to send the battery information via telemetry since not always the flight controller transmits that information by default.

