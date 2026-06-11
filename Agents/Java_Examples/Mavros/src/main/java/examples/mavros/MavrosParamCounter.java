package examples.mavros;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.BufferedWriter;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Locale;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

public class MavrosParamCounter {
    private static final String PARAM_ID = "MPC_Z_VEL_MAX_UP";
    private static final int LIMIT_STEP = 100;
    private static final double FIRST_VALUE = 1.0;
    private static final long JASON_WAIT_MS = 120;
    private static final String PARAM_EVENT_TOPIC = "/mavros/param/event";
    private static final String PARAM_SET_SERVICE = "/mavros/param/set_parameters";

    private final ObjectMapper mapper = new ObjectMapper();
    private final CountDownLatch finished = new CountDownLatch(1);
    private final AtomicBoolean awaitingReadback = new AtomicBoolean(false);
    private final ScheduledExecutorService jasonWaitScheduler =
            Executors.newSingleThreadScheduledExecutor(r -> {
                Thread thread = new Thread(r, "jason-like-wait");
                thread.setDaemon(true);
                return thread;
            });

    private WebSocket webSocket;
    private BufferedWriter timeLog;
    private ScheduledFuture<?> pendingJasonWait;
    private int step = 0;
    private double expectedValue = FIRST_VALUE;

    public static void main(String[] args) throws Exception {
        String rosbridgeUrl = args.length > 0 ? args[0] : "ws://localhost:9090";
        new MavrosParamCounter().run(rosbridgeUrl);
    }

    private void run(String rosbridgeUrl) throws Exception {
        Path logPath = nextTimeLogPath(Path.of("log"));
        Files.createDirectories(logPath.getParent());

        try (BufferedWriter writer = Files.newBufferedWriter(logPath, StandardCharsets.UTF_8)) {
            timeLog = writer;
            connect(rosbridgeUrl);
            subscribeParamEvents();

            System.out.println("Writing timing samples to " + logPath);
            System.out.println("Starting MAVROS Java parameter counter at 1.");
            Thread.sleep(500);

            awaitingReadback.set(true);
            sendParamSet(expectedValue);

            boolean done = finished.await(120, TimeUnit.SECONDS);
            if (!done) {
                throw new IllegalStateException("Timed out waiting for parameter counter to finish.");
            }
        } finally {
            jasonWaitScheduler.shutdownNow();
            if (webSocket != null) {
                webSocket.sendClose(WebSocket.NORMAL_CLOSURE, "done").join();
            }
        }
    }

    private void connect(String rosbridgeUrl) {
        webSocket = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .build()
                .newWebSocketBuilder()
                .connectTimeout(Duration.ofSeconds(10))
                .buildAsync(URI.create(rosbridgeUrl), new RosbridgeListener())
                .join();
    }

    private void subscribeParamEvents() {
        ObjectNode subscribe = mapper.createObjectNode();
        subscribe.put("op", "subscribe");
        subscribe.put("topic", PARAM_EVENT_TOPIC);
        subscribe.put("type", "mavros_msgs/msg/ParamEvent");
        sendJson(subscribe);
    }

    private synchronized void onParamEvent(JsonNode event) {
        if (!awaitingReadback.get()) {
            return;
        }

        JsonNode msg = event.path("msg");
        String paramId = msg.path("param_id").asText();
        double value = msg.path("value").path("double_value").asDouble(Double.NaN);

        if (!PARAM_ID.equals(paramId) || Double.compare(value, expectedValue) != 0) {
            return;
        }

        awaitingReadback.set(false);
        finishJasonWaitWindow();
        long timestamp = System.nanoTime();

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
            System.out.println("MAVROS Java parameter counter finished at value " + formatValue(value) + ".");
            finished.countDown();
        }
    }

    private void sendParamSet(double value) {
        ObjectNode request = mapper.createObjectNode();
        request.put("op", "call_service");
        request.put("service", PARAM_SET_SERVICE);

        ObjectNode args = mapper.createObjectNode();
        ArrayNode parameters = args.putArray("parameters");
        ObjectNode parameter = parameters.addObject();
        parameter.put("name", PARAM_ID);

        ObjectNode parameterValue = parameter.putObject("value");
        parameterValue.put("type", 3);
        parameterValue.put("bool_value", false);
        parameterValue.put("integer_value", 0);
        parameterValue.put("double_value", value);
        parameterValue.put("string_value", "unused");
        parameterValue.putArray("byte_array_value");
        parameterValue.putArray("bool_array_value");
        parameterValue.putArray("integer_array_value");
        parameterValue.putArray("double_array_value");
        parameterValue.putArray("string_array_value");

        request.set("args", args);
        sendJson(request);
    }

    private void sendParamSetWithJasonWait(double value) {
        sendParamSet(value);
        startJasonWaitWindow();
    }

    private void sendJson(ObjectNode node) {
        try {
            webSocket.sendText(mapper.writeValueAsString(node), true).join();
        } catch (Exception e) {
            finished.countDown();
            throw new RuntimeException("Failed to send rosbridge message.", e);
        }
    }

    private synchronized void startJasonWaitWindow() {
        finishJasonWaitWindow();
        pendingJasonWait = jasonWaitScheduler.schedule(() -> {
            synchronized (MavrosParamCounter.this) {
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

    private class RosbridgeListener implements WebSocket.Listener {
        private final StringBuilder partial = new StringBuilder();

        @Override
        public void onOpen(WebSocket webSocket) {
            webSocket.request(1);
        }

        @Override
        public CompletionStage<?> onText(WebSocket webSocket, CharSequence data, boolean last) {
            partial.append(data);
            if (last) {
                String text = partial.toString();
                partial.setLength(0);
                try {
                    JsonNode event = mapper.readTree(text);
                    if ("publish".equals(event.path("op").asText())
                            && PARAM_EVENT_TOPIC.equals(event.path("topic").asText())) {
                        onParamEvent(event);
                    }
                } catch (Exception e) {
                    System.err.println("Ignoring malformed rosbridge message: " + e.getMessage());
                }
            }
            webSocket.request(1);
            return null;
        }

        @Override
        public void onError(WebSocket webSocket, Throwable error) {
            error.printStackTrace();
            finished.countDown();
        }
    }
}
