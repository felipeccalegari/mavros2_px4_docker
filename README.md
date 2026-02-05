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

*Jason Agent code in the /Agent folder
```
./gradlew run
```
