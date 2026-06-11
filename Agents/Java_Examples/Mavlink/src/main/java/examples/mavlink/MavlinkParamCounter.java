package examples.mavlink;

import com.fazecast.jSerialComm.SerialPort;
import io.dronefleet.mavlink.MavlinkConnection;
import io.dronefleet.mavlink.MavlinkMessage;
import io.dronefleet.mavlink.common.MavParamType;
import io.dronefleet.mavlink.common.ParamSet;
import io.dronefleet.mavlink.common.ParamValue;
import io.dronefleet.mavlink.minimal.Heartbeat;
import io.dronefleet.mavlink.minimal.MavAutopilot;
import io.dronefleet.mavlink.minimal.MavModeFlag;
import io.dronefleet.mavlink.minimal.MavState;
import io.dronefleet.mavlink.minimal.MavType;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

public class MavlinkParamCounter {
    private static final String PARAM_ID = "MPC_Z_VEL_MAX_UP";
    private static final int LIMIT_STEP = 100;
    private static final double FIRST_VALUE = 1.0;
    private static final long JASON_WAIT_MS = 120;
    private static final int SYSTEM_ID = 255;
    private static final int COMPONENT_ID = 190;
    private static final int TARGET_SYSTEM = 1;
    private static final int TARGET_COMPONENT = 1;

    private final CountDownLatch finished = new CountDownLatch(1);
    private final AtomicBoolean running = new AtomicBoolean(true);
    private final AtomicBoolean awaitingReadback = new AtomicBoolean(false);
    private final ScheduledExecutorService jasonWaitScheduler =
            Executors.newSingleThreadScheduledExecutor(r -> {
                Thread thread = new Thread(r, "jason-like-wait");
                thread.setDaemon(true);
                return thread;
            });

    private MavlinkConnection connection;
    private SerialPort serialPort;
    private BufferedWriter timeLog;
    private ScheduledFuture<?> pendingJasonWait;
    private int step = 0;
    private double expectedValue = FIRST_VALUE;

    public static void main(String[] args) throws Exception {
        String serialDevice = args.length > 0 ? args[0] : "/dev/ttyV1";
        int baudRate = args.length > 1 ? Integer.parseInt(args[1]) : 57600;
        new MavlinkParamCounter().run(serialDevice, baudRate);
    }

    private void run(String serialDevice, int baudRate) throws Exception {
        Path logPath = nextTimeLogPath(Path.of("log"));
        Files.createDirectories(logPath.getParent());

        try (BufferedWriter writer = Files.newBufferedWriter(logPath, StandardCharsets.UTF_8)) {
            timeLog = writer;
            openSerial(serialDevice, baudRate);

            System.out.println("Writing timing samples to " + logPath);
            System.out.println("Starting direct MAVLink Java parameter counter at 1.");

            Thread reader = new Thread(this::readLoop, "mavlink-param-reader");
            reader.setDaemon(true);
            reader.start();

            Thread heartbeat = new Thread(this::heartbeatLoop, "mavlink-heartbeat");
            heartbeat.setDaemon(true);
            heartbeat.start();

            Thread.sleep(500);
            awaitingReadback.set(true);
            sendParamSet(expectedValue);

            boolean done = finished.await(120, TimeUnit.SECONDS);
            if (!done) {
                throw new IllegalStateException("Timed out waiting for parameter counter to finish.");
            }
        } finally {
            running.set(false);
            jasonWaitScheduler.shutdownNow();
            if (serialPort != null) {
                serialPort.closePort();
            }
        }
    }

    private void openSerial(String serialDevice, int baudRate) {
        serialPort = SerialPort.getCommPort(serialDevice);
        serialPort.setComPortParameters(baudRate, 8, SerialPort.ONE_STOP_BIT, SerialPort.NO_PARITY);
        serialPort.setComPortTimeouts(SerialPort.TIMEOUT_READ_BLOCKING, 1000, 0);

        if (!serialPort.openPort()) {
            throw new IllegalStateException("Could not open serial port " + serialDevice);
        }

        connection = MavlinkConnection.create(serialPort.getInputStream(), serialPort.getOutputStream());
    }

    private void readLoop() {
        while (running.get()) {
            try {
                MavlinkMessage<?> message = connection.next();
                if (message == null || !(message.getPayload() instanceof ParamValue)) {
                    continue;
                }

                ParamValue paramValue = (ParamValue) message.getPayload();
                onParamValue(paramValue);
            } catch (IOException e) {
                if (running.get()) {
                    System.err.println("MAVLink read failed: " + e.getMessage());
                }
            }
        }
    }

    private synchronized void onParamValue(ParamValue paramValue) {
        if (!awaitingReadback.get()
                || !PARAM_ID.equals(paramValue.paramId())
                || Float.compare(paramValue.paramValue(), (float) expectedValue) != 0) {
            return;
        }

        awaitingReadback.set(false);
        finishJasonWaitWindow();
        long timestamp = System.nanoTime();
        double value = paramValue.paramValue();

        try {
            timeLog.write(timestamp + ";" + step + ";" + formatValue(value));
            timeLog.newLine();
            timeLog.flush();
        } catch (IOException e) {
            finished.countDown();
            throw new RuntimeException("Failed to write timing log.", e);
        }

        System.out.println(timestamp + ";" + step + ";" + formatValue(value));

        if (step < LIMIT_STEP) {
            step++;
            expectedValue += 1.0;
            awaitingReadback.set(true);
            sendParamSetWithJasonWait(expectedValue);
        } else {
            System.out.println("MAVLink Java parameter counter finished at value " + formatValue(value) + ".");
            finished.countDown();
        }
    }

    private void sendParamSet(double value) {
        ParamSet paramSet = ParamSet.builder()
                .targetSystem(TARGET_SYSTEM)
                .targetComponent(TARGET_COMPONENT)
                .paramId(PARAM_ID)
                .paramValue((float) value)
                .paramType(MavParamType.MAV_PARAM_TYPE_REAL32)
                .build();
        sendMavlink(paramSet);
    }

    private void sendParamSetWithJasonWait(double value) {
        sendParamSet(value);
        startJasonWaitWindow();
    }

    private void heartbeatLoop() {
        while (running.get()) {
            try {
                sendHeartbeat();
                Thread.sleep(250);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            } catch (Exception e) {
                if (running.get()) {
                    System.err.println("Heartbeat send failed: " + e.getMessage());
                }
            }
        }
    }

    private void sendHeartbeat() {
        Heartbeat heartbeat = Heartbeat.builder()
                .type(MavType.MAV_TYPE_GCS)
                .autopilot(MavAutopilot.MAV_AUTOPILOT_INVALID)
                .baseMode(MavModeFlag.MAV_MODE_FLAG_CUSTOM_MODE_ENABLED)
                .customMode(0)
                .systemStatus(MavState.MAV_STATE_ACTIVE)
                .mavlinkVersion(3)
                .build();
        sendMavlink(heartbeat);
    }

    private synchronized void sendMavlink(Object payload) {
        try {
            connection.send2(SYSTEM_ID, COMPONENT_ID, payload);
        } catch (IOException e) {
            finished.countDown();
            throw new RuntimeException("Failed to send MAVLink payload.", e);
        }
    }

    private synchronized void startJasonWaitWindow() {
        finishJasonWaitWindow();
        pendingJasonWait = jasonWaitScheduler.schedule(() -> {
            synchronized (MavlinkParamCounter.this) {
                pendingJasonWait = null;
            }
        }, JASON_WAIT_MS, TimeUnit.MILLISECONDS);
    }

    private synchronized void finishJasonWaitWindow() {
        if (pendingJasonWait != null) {
            pendingJasonWait.cancel(false);
            pendingJasonWait = null;
        }
    }

    private static Path nextTimeLogPath(Path logDir) throws IOException {
        Files.createDirectories(logDir);
        int index = 0;
        while (Files.exists(logDir.resolve("times_" + index + ".log"))) {
            index++;
        }
        return logDir.resolve("times_" + index + ".log");
    }

    private static String formatValue(double value) {
        return String.format(Locale.US, "%.1f", value);
    }
}
