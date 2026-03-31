import embedded.mas.bridges.ros.IRosInterface;
import embedded.mas.bridges.ros.RosMaster;
import embedded.mas.bridges.ros.DefaultRos4EmbeddedMas;

import jason.asSyntax.Atom;
import jason.asSyntax.ListTermImpl;
import jason.asSyntax.Term;
import jason.asSemantics.Unifier;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

public class CustomClass extends RosMaster{

    public CustomClass(Atom id, IRosInterface microcontroller) {
        super(id, microcontroller);
    }

    @Override
   public boolean execEmbeddedAction(String actionName, Object[] args, Unifier un) {		
	//execute the actions configured in the yaml file
        super.execEmbeddedAction(actionName, args, un);  // <- do not delete this line - it executes the actions configured in the yaml file

	//*** Handle customized actions after this point ****

    if (actionName.equals("mission_push")) {
        if (args == null || args.length < 2 || args[0] == null || args[1] == null) return false;

        ListTermImpl start_index = (ListTermImpl) args[0];
        if (start_index == null || start_index.size() < 1) return false;
        Term s_index = start_index.get(0);
        if (s_index == null) return false;

        ListTermImpl waypoints = (ListTermImpl) args[1];
        if (waypoints == null) return false;

        StringBuilder waypointsJson = new StringBuilder("[");
        for (int i = 0; i < waypoints.size(); i++) {
            if (i > 0) waypointsJson.append(",");
            ListTermImpl waypoint = (ListTermImpl) waypoints.get(i);
            if (waypoint == null || waypoint.size() < 11) return false;  // ✅ bounds check

            Term[] fields = new Term[11];
            for (int j = 0; j < 11; j++) {
                fields[j] = waypoint.get(j);
                if (fields[j] == null) return false;  // ✅ null check per field
            }
            waypointsJson.append("{\"frame\":").append(fields[0])
                .append(",\"command\":").append(fields[1])
                .append(",\"is_current\":").append(fields[2])
                .append(",\"autocontinue\":").append(fields[3])
                .append(",\"param1\":").append(fields[4])
                .append(",\"param2\":").append(fields[5])
                .append(",\"param3\":").append(fields[6])
                .append(",\"param4\":").append(fields[7])
                .append(",\"x_lat\":").append(fields[8])
                .append(",\"y_long\":").append(fields[9])
                .append(",\"z_alt\":").append(fields[10]).append("}");
        }
        waypointsJson.append("]");

        String jsonString = "{\"start_index\":" + s_index + ",\"waypoints\":" + waypointsJson + "}";
        try {
            ObjectMapper mapper = new ObjectMapper();
            JsonNode jsonNode = mapper.readTree(jsonString);
            if (jsonNode == null) return false;
            ((DefaultRos4EmbeddedMas) this.getMicrocontroller()).serviceRequest("/mavros/mission/push", jsonNode);
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
        return true;  // ✅ early return
    }

    if (actionName.equals("rc_override")) {
        if (args == null || args.length < 1 || args[0] == null) return false;
        ListTermImpl channels = (ListTermImpl) args[0];
        if (channels == null) return false;

        StringBuilder sb = new StringBuilder("{\"channels\":[");
        int i = 0;
        for (Term t : channels) {
            if (i >= 18) break;
            int v = 65535;
            if (t != null) {  // ✅ null check per term
                try { v = Integer.parseInt(t.toString()); }
                catch (Exception ex) { v = 65535; }
                if (v < 0) v = 0;
                if (v > 65535) v = 65535;
            }
            if (i > 0) sb.append(",");
            sb.append(v);
            i++;
        }
        while (i++ < 18) sb.append(",65535");
        sb.append("]}");

        ((DefaultRos4EmbeddedMas) this.getMicrocontroller())
            .rosWrite("/mavros/rc/override", "mavros_msgs/msg/OverrideRCIn", sb.toString());
        return true;
    }

    if (actionName.equals("param_set")) {
        if (args == null || args.length < 3) return false;

        String paramId = args[1].toString().replaceAll("^\"|\"$", "");

        ListTermImpl value;
        if (args[2] instanceof ListTermImpl) {
            value = (ListTermImpl) args[2];
        } else {
            return false;
        }
        if (value.size() < 4) return false;

        int type = Integer.parseInt(value.get(0).toString());
        boolean boolValue = Boolean.parseBoolean(value.get(1).toString());
        long integerValue = Long.parseLong(value.get(2).toString());
        double doubleValue = Double.parseDouble(value.get(3).toString());

        String jsonString =
            "{"
            + "\"parameters\":[{"
                + "\"name\":\"" + paramId + "\","
                + "\"value\":{"
                    + "\"type\":" + type + ","
                    + "\"bool_value\":" + boolValue + ","
                    + "\"integer_value\":" + integerValue + ","
                    + "\"double_value\":" + doubleValue + ","
                    + "\"string_value\":\"unused\","
                    + "\"byte_array_value\":[],"
                    + "\"bool_array_value\":[],"
                    + "\"integer_array_value\":[],"
                    + "\"double_array_value\":[],"
                    + "\"string_array_value\":[]"
                + "}"
            + "}]"
            + "}";

        try {
            JsonNode jsonNode = new ObjectMapper().readTree(jsonString);
            ((DefaultRos4EmbeddedMas) this.getMicrocontroller())
                .serviceRequest("/mavros/param/set_parameters", jsonNode);
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

       return true;
}

}
