import embedded.mas.bridges.ros.IRosInterface;
import embedded.mas.bridges.ros.RosMaster;
import embedded.mas.bridges.ros.DefaultRos4EmbeddedMas;

import jason.asSyntax.Atom;
import jason.asSyntax.ListTermImpl;
import jason.asSyntax.Literal;
import jason.asSyntax.NumberTermImpl;
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
          
	
	
	
	// Handling the action "mission_push", which is realized by requesting the ROS service 		
	
	if(actionName.equals("mission_push")){ // <- mission_push is the name of the internal action used in the .asl code
	   ListTermImpl start_index = (ListTermImpl)args[0]; // 1st parameter
    Term s_index = start_index.get(0);
    
    ListTermImpl waypoints = (ListTermImpl)args[1]; // 2nd parameter - list of waypoints
    
    // Build waypoints array
    StringBuilder waypointsJson = new StringBuilder("[");
    
    for(int i = 0; i < waypoints.size(); i++){
        if(i > 0) waypointsJson.append(",");
        
        ListTermImpl waypoint = (ListTermImpl)waypoints.get(i); // Each waypoint is a list
        Term frame = waypoint.get(0);
        Term command = waypoint.get(1);
        Term is_current = waypoint.get(2);
        Term autocontinue = waypoint.get(3);
        Term param1 = waypoint.get(4);
        Term param2 = waypoint.get(5);
        Term param3 = waypoint.get(6);
        Term param4 = waypoint.get(7);
        Term x_lat = waypoint.get(8);
        Term y_long = waypoint.get(9);
        Term z_alt = waypoint.get(10);
        
        waypointsJson.append("{\"frame\":").append(frame.toString()).append(",")
                     .append("\"command\":").append(command.toString()).append(",")
                     .append("\"is_current\":").append(is_current.toString()).append(",")
                     .append("\"autocontinue\":").append(autocontinue.toString()).append(",")
                     .append("\"param1\":").append(param1.toString()).append(",")
                     .append("\"param2\":").append(param2.toString()).append(",")
                     .append("\"param3\":").append(param3.toString()).append(",")
                     .append("\"param4\":").append(param4.toString()).append(",")
                     .append("\"x_lat\":").append(x_lat.toString()).append(",")
                     .append("\"y_long\":").append(y_long.toString()).append(",")
                     .append("\"z_alt\":").append(z_alt.toString()).append("}");
    }
    
    waypointsJson.append("]");
    
    String jsonString = "{\"start_index\":" + s_index.toString() + "," + "\"waypoints\":" + waypointsJson.toString() + "}";


	   /* Term linear = (Term)args[0]; //assign the first parameter to the variable "linear"
	   Term angular = (Term)args[1]; //assign the second parameter to the variable "angular"
	   
	   //build a JSON object with the parameters required by the ROS service
   	   String jsonString = "{\"linear\":"+linear.toString()+",\"angular\":"+angular.toString()+"}"; */
   	   ObjectMapper mapper = new ObjectMapper();
   	   JsonNode jsonNode = null;
           try {
              // Convert a String into JsonNode
	      jsonNode = mapper.readTree(jsonString);
	   }catch(Exception e) {
	     return false;
	   }

           //Requesting the service
	   ((DefaultRos4EmbeddedMas) this.getMicrocontroller()).serviceRequest("/mavros/mission/push",jsonNode);
		
       }

		

       return true;
}

}
