**Custom Docker image for PX4 1.16 + MAVROS2 Humble.**

- Build the image:
```
docker-compose up --build
```

- Run the container:
```
xhost +local:docker
docker compose up -d
```

- Execute container commands:
```
docker exec -it px4_ros2 bash
```

- Execute the simulation:
```
make px4_sitl gz_x500
```

*Jason Agent code in the /Agents/Mavros folder
```
cd Agents/Mavros
chmod +x gradlew
./gradlew run
```

- The file `px4_mavlink_mavros_mapping.xlsx` has been generated to be used as reference to map most Mavros and Mavlink commands/messages available in the current system.
