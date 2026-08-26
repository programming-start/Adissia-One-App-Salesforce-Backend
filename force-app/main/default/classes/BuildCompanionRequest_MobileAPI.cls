/**
 * Author     : Sivam V
 * Class Name : BuildCompanionRequest_MobileAPI
 * API Name   : BuildCompanionRequest API
 * REST Method: GET & POST
 * Purpose    : Build Companion module (v1).
 *              GET  ?type=form              -> form definition (Request Type options + Description field)
 *              GET  ?type=status&customerId -> status list of the customer's requests (number + status)
 *              POST { customerId, description } -> creates a request, returns the auto-generated number
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/BuildCompanionRequestAPI/*')
global without sharing class BuildCompanionRequest_MobileAPI {

    // Request Type picklist values (kept here so the form can be changed in one place)
    private static final List<String> REQUEST_TYPES = new List<String>{
        'Build a Home', 'Building Approval', 'Registration', 'Architect',
        'Structural Drawing', 'Interior Design', 'Vaastu', 'Fencing Construction',
        'Borewell Construction', 'NRI care Property care', 'Landscaping Property care',
        'Land survey Approval', 'Loan', 'Other Enquiry'
    };

    // ============================================================ GET (form / status)
    @HttpGet
    global static void handleGet() {
        RestRequest request = RestContext.request;
        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c = 'BuildCompanionRequestAPI';

        try {
            String type = request.params.get('type');
            log.Request__c = 'GET type=' + type;

            if (type == 'status') {
                getStatus(request, log);
            } else {
                // default / type=form -> return the form definition
                getForm(log);
            }
        } catch (Exception e) {
            log.response__c = e.getStackTraceString();
            log.Status__c = 'FAIL';
            log.Error_Message__c = e.getMessage();
            insert log;
            sendErrorResponse('Error: ' + e.getMessage());
        }
    }

    // GET ?type=form -> Request Type options + the Description field
    private static void getForm(Apex_Log__c log) {
        List<FieldOption> requestTypeOptions = new List<FieldOption>();
        for (String rt : REQUEST_TYPES) {
            FieldOption option = new FieldOption();
            option.label = rt;
            option.value = rt;
            requestTypeOptions.add(option);
        }

        List<FormField> fields = new List<FormField>();
        fields.add(makeSelectField('requestType', 'Request Type', 'select', true, requestTypeOptions));
        fields.add(makeField('description', 'Description', 'textarea', true));

        FormResponse response = new FormResponse();
        response.success = true;
        response.message = 'Build companion form fetched successfully';
        response.data = new FormData();
        response.data.formTitle = 'Build Companion Request';
        response.data.submitEndpoint = '/services/apexrest/BuildCompanionRequestAPI';
        response.data.submitMethod = 'POST';
        response.data.fields = fields;

        log.response__c = 'Form fetched successfully';
        log.Status__c = 'SUCCESS';
        insert log;

        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    // GET ?type=status&customerId=AID3147 -> all the customer's build companion requests
    private static void getStatus(RestRequest request, Apex_Log__c log) {
        String customerId = request.params.get('customerId');
        log.Request__c = 'GET status customerId=' + customerId;

        if (String.isBlank(customerId)) {
            log.response__c = 'Customer Id should not be blank';
            log.Status__c = 'SUCCESS';
            insert log;
            sendErrorResponse('Customer Id should not be blank');
            return;
        }

        List<Customer_Master__c> cmList = [SELECT Id FROM Customer_Master__c WHERE Name = :customerId AND isActive__c = TRUE LIMIT 1];
        if (cmList.isEmpty()) {
            log.response__c = 'Customer Not Found';
            log.Status__c = 'SUCCESS';
            insert log;
            sendErrorResponse('Customer Not Found');
            return;
        }

        List<StatusData> statusList = new List<StatusData>();
        for (Build_Companion_Request__c bcr : [SELECT Id, Name, Request_Type__c, Status__c, Description__c, CreatedDate FROM Build_Companion_Request__c WHERE Customer_Master__c = :cmList[0].Id ORDER BY CreatedDate DESC]) {
            StatusData sd = new StatusData();
            sd.requestNumber = bcr.Name;
            sd.requestType = safe(bcr.Request_Type__c);
            sd.status = String.isBlank(bcr.Status__c) ? 'Pending' : bcr.Status__c;
            sd.description = safe(bcr.Description__c);
            sd.createdDate = String.valueOf(bcr.CreatedDate);
            statusList.add(sd);
        }

        StatusResponse response = new StatusResponse();
        response.success = true;
        response.message = 'Status fetched successfully';
        response.data = new StatusResponseData();
        response.data.requests = statusList;

        log.response__c = 'Status fetched successfully for ' + customerId;
        log.Status__c = 'SUCCESS';
        insert log;

        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    // ============================================================ POST (create)
    @HttpPost
    global static void createBuildCompanionRequest() {
        RestRequest req = RestContext.request;
        String requestBody = req.requestBody.toString(); // Get the JSON body
        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c = 'BuildCompanionRequestAPI';
        log.Request__c = requestBody;

        try {
            BuildCompanionWrapper proj = (BuildCompanionWrapper) JSON.deserialize(requestBody, BuildCompanionWrapper.class);
            String customerId = proj.customerId;
            String description = proj.description;
            String requestType = proj.requestType;

            if (String.isBlank(customerId)) {
                log.response__c = 'Customer Id should not be blank';
                log.Status__c = 'SUCCESS';
                insert log;
                sendErrorResponse('Customer Id should not be blank');
                return;
            }

            List<Customer_Master__c> cmList = [SELECT Id, Name FROM Customer_Master__c WHERE Name = :customerId AND isActive__c = TRUE LIMIT 1];
            if (cmList.isEmpty()) {
                log.response__c = 'Customer Not Found';
                log.Status__c = 'SUCCESS';
                insert log;
                sendErrorResponse('Customer Not Found');
                return;
            }

            Build_Companion_Request__c buildCompanionRequest = new Build_Companion_Request__c();
            buildCompanionRequest.Customer_Master__c = cmList[0].Id;
            buildCompanionRequest.Description__c = description;
            if (String.isNotBlank(requestType)) {
                buildCompanionRequest.Request_Type__c = requestType;
            }
            buildCompanionRequest.Status__c = 'Pending';

            // Owner = the owner of the customer's Customer Delight record (created at
            // booking -> registration), resolved via the customer's booking. Falls back to
            // the existing CD owner resolver if no CD record is found.
            Id cdOwnerId = getCustomerDelightRecordOwner(cmList[0].Id);
            if (cdOwnerId == null) {
                cdOwnerId = BuildCompanionNotifier.getCustomerDelightOwnerId(cmList[0].Id);
            }
            if (cdOwnerId != null) {
                buildCompanionRequest.OwnerId = cdOwnerId;
            }

            insert buildCompanionRequest;

            BuildCompanionNotifier.notifyOwner(buildCompanionRequest.Id, cdOwnerId);

            // Fetch the generated auto-number to return to the app
            Build_Companion_Request__c created = [SELECT Name FROM Build_Companion_Request__c WHERE Id = :buildCompanionRequest.Id LIMIT 1];

            log.response__c = 'Build companion request created successfully by ' + customerId + ' : ' + created.Name;
            log.Status__c = 'SUCCESS';
            insert log;

            sendSuccessResponse(created.Name);

        } catch (Exception e) {
            log.response__c = e.getStackTraceString();
            log.Status__c = 'FAIL';
            log.Error_Message__c = e.getMessage();
            insert log;
            sendErrorResponse('Error: ' + e.getMessage());
        }
    }

    // Owner of the customer's Customer Delight record (via their booking).
    // Returns the standard record OwnerId of the most recent CD record, or null.
    private static Id getCustomerDelightRecordOwner(Id customerMasterId) {
        List<Customer_Delight__c> cdList = [SELECT Id, OwnerId__c FROM Customer_Delight__c WHERE Booking__r.Customer_Master__c = :customerMasterId ORDER BY CreatedDate DESC LIMIT 1];
        return cdList.isEmpty() ? null : cdList[0].OwnerId__c;
    }

    private static String safe(String value) {
        return value == null ? '' : value;
    }

    // ----------------------------------------------------------------- WRAPPERS
    public class BuildCompanionWrapper {
        public String customerId;
        public String description;
        public String requestType;
    }

    // GET form wrappers
    public class FormResponse {
        public Boolean success;
        public String message;
        public FormData data;
    }
    public class FormData {
        public String formTitle;
        public String submitEndpoint;
        public String submitMethod;
        public List<FormField> fields;
    }
    public class FormField {
        public String key;
        public String label;
        public String type;
        public Boolean required;
        public List<FieldOption> options;
    }
    public class FieldOption {
        public String label;
        public String value;
    }

    // GET status wrappers
    public class StatusResponse {
        public Boolean success;
        public String message;
        public StatusResponseData data;
    }
    public class StatusResponseData {
        public List<StatusData> requests;
    }
    public class StatusData {
        public String requestNumber;
        public String requestType;
        public String status;
        public String description;
        public String createdDate;
    }

    // POST response wrapper
    public class ResponseWrapper {
        public Boolean success;
        public String message;
        public String requestId;
    }

    private static FormField makeField(String key, String label, String type, Boolean required) {
        FormField field = new FormField();
        field.key = key;
        field.label = label;
        field.type = type;
        field.required = required;
        return field;
    }
    private static FormField makeSelectField(String key, String label, String type, Boolean required, List<FieldOption> options) {
        FormField field = makeField(key, label, type, required);
        field.options = options;
        return field;
    }

    private static void sendSuccessResponse(String reqNumber) {
        ResponseWrapper response = new ResponseWrapper();
        response.success = true;
        response.message = 'Request created successfully';
        response.requestId = reqNumber;

        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }
    private static void sendErrorResponse(String message) {
        ResponseWrapper response = new ResponseWrapper();
        response.success = false;
        response.message = message;

        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }
}