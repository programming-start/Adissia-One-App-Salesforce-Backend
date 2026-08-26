/**
 * Author     : Sivam V
 * Class Name : SiteVisitForm_MobileAPI
 * API Name   : SiteVisitForm API
 * REST Method: GET
 * Purpose    : Returns the dynamic form definition for the "Book a Site Visit"
 *              screen. The frontend renders the form generically from this JSON
 *              (field key, label, type, required, options), then POSTs the filled
 *              values to ScheduleSiteVisitAPI. The project dropdown options are the
 *              live projects, so no app release is needed when projects change.
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/SiteVisitForm/*')
global without sharing class SiteVisitForm_MobileAPI {

    @HttpGet
    global static void getSiteVisitForm() {
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'SiteVisitForm_MobileAPI';
        apexLog.Request__c = 'GET site visit form';

        try {
            // Live project options for the project dropdown (value = Name, since the
            // booking API matches the project by Name).
            List<FieldOption> projectOptions = new List<FieldOption>();
            for (Project__c project : [SELECT Name, Project_Id__c FROM Project__c WHERE Project_Status__c != NULL AND Project_Status__c = 'Ongoing'
             ORDER BY Name ASC]) {
                FieldOption option = new FieldOption();
                option.label = project.Name;
                option.value = project.Name;
                option.projectId = project.Project_Id__c;
                projectOptions.add(option);
            }

            List<FormField> fields = new List<FormField>();
            fields.add(makeField('projectId', 'Project', 'select', true, projectOptions));
            fields.add(makeField('svDate', 'Preferred Date', 'date', true, null));
            fields.add(makeField('svTime', 'Preferred Time', 'time', true, null));

            FormResponse response = new FormResponse();
            response.success = true;
            response.message = 'Site visit form fetched successfully';
            response.data = new FormData();
            response.data.formTitle = 'Book a Site Visit';
            response.data.submitEndpoint = '/services/apexrest/ScheduleSiteVisitAPI';
            response.data.submitMethod = 'POST';
            response.data.fields = fields;
            response.data.submitNote = 'Combine svDate + svTime into a single ISO datetime and send it as svdate to the submit endpoint, along with userId, lastName and phoneNumber from the session.';

            apexLog.response__c = 'Site visit form fetched successfully';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;

            RestContext.response.statusCode = 200;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));

        } catch (Exception caughtException) {
            apexLog.response__c = caughtException.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = caughtException.getMessage();
            insert apexLog;
            sendErrorResponse('Error: ' + caughtException.getMessage());
        }
    }

    private static FormField makeField(String key, String label, String type, Boolean required, List<FieldOption> options) {
        FormField field = new FormField();
        field.key = key;
        field.label = label;
        field.type = type;
        field.required = required;
        field.options = options;
        return field;
    }

    // ----------------------------------------------------------------- WRAPPERS
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
        public String submitNote; // how to build the POST body
    }
    public class FormField {
        public String key;         // the JSON key to send back (matches ScheduleSiteVisitAPI)
        public String label;       // what to show the user
        public String type;        // text | email | phone | select | datetime
        public Boolean required;
        public List<FieldOption> options; // only for select; null otherwise
    }
    public class FieldOption {
        public String label;
        public String value;
        public String projectId;
    }

    private static void sendErrorResponse(String message) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        }));
    }
}