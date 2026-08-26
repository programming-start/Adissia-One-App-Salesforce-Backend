/**
 * Author     : Sivam V
 * Class Name : ReferAFriend_MobileAPI
 * API Name   : ReferAFriend API
 * REST Method: GET & POST
 * Purpose    : Create a referral Lead from the "Refer a Friend" form in the Adissia
 *              One app. The referrer is the logged-in customer (userId / AID); their
 *              name + phone are looked up and stamped as the referrer on the Lead.
 *              Referral Campaign / Sub Campaign come from the Constants class so they
 *              can be changed in one place. Every referral lead is owned by the fixed
 *              Referral Sales user (pooja@adissia.com), who is also the enquiry source.
 * Date       : 06/07/2026
 */

@RestResource(urlMapping='/ReferAFriend/*')
global without sharing class ReferAFriend_MobileAPI {

    // Fixed owner for all mobile-referral leads (Referral Sales).
    private static final String REFERRAL_OWNER_USERNAME = 'pooja@adissia.com';
    private static final String OWNER_CHANGED_NOTIFICATION = 'Lead_Assignment_Notification_Owner_Changed';

    // -------------------------------------------------------------- GET: form definition
    // Returns the "Refer a Friend" form fields for the app to render dynamically.
    // The user fills these and POSTs them back to this same endpoint.
    @HttpGet
    global static void getReferralForm() {
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'ReferAFriend_MobileAPI';
        apexLog.Request__c = 'GET refer a friend form';

        try {
            // Live project options for the required project dropdown
            List<FieldOption> projectOptions = new List<FieldOption>();
            for (Project__c project : [SELECT Name, Project_Id__c FROM Project__c WHERE Project_Status__c != NULL ORDER BY Name ASC]) {
                FieldOption option = new FieldOption();
                option.label = project.Name;
                option.value = project.Name;
                option.projectId = project.Project_Id__c;
                projectOptions.add(option);
            }

            List<FormField> fields = new List<FormField>();
            // Referrer (the app user types their own details)
            fields.add(makeField('referrerName', 'Your Name', 'text', true));
            fields.add(makeField('referrerPhone', 'Your Mobile Number', 'phone', true));
            fields.add(makeField('purpose', 'Purpose', 'text', true));
            // Project (required dropdown)
            fields.add(makeSelectField('projectName', 'Project', 'select', true, projectOptions));
            // Friend (the referred person)
            fields.add(makeField('firstName', 'Friend First Name', 'text', false));
            fields.add(makeField('lastName', 'Friend Last Name', 'text', true));
            fields.add(makeField('primaryPhone', 'Friend Primary Mobile', 'phone', true));
            fields.add(makeField('secondaryPhone', 'Friend Secondary Mobile', 'phone', false));

            FormResponse response = new FormResponse();
            response.success = true;
            response.message = 'Refer a friend form fetched successfully';
            response.data = new FormData();
            response.data.formTitle = 'Refer a Friend';
            response.data.submitEndpoint = '/services/apexrest/ReferAFriend';
            response.data.submitMethod = 'POST';
            response.data.fields = fields;

            apexLog.response__c = 'Refer a friend form fetched successfully';
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

    @HttpPost
    global static void referAFriend() {
        RestRequest request = RestContext.request;
        String requestBody = request.requestBody.toString(); // Get the JSON body
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'ReferAFriend_MobileAPI';
        apexLog.Request__c = requestBody;

        try {
            ReferralWrapper requestWrapper = (ReferralWrapper) JSON.deserialize(requestBody, ReferralWrapper.class);
            String userId = requestWrapper.userId;
            String firstName = requestWrapper.firstName;
            String lastName = requestWrapper.lastName;
            String primaryPhone = requestWrapper.primaryPhone;
            String secondaryPhone = requestWrapper.secondaryPhone;
            String referrerName = requestWrapper.referrerName;
            String referrerPhone = requestWrapper.referrerPhone;
            String purpose = requestWrapper.purpose;
            String projectName = requestWrapper.projectName;

            // Friend last name + primary phone are required; referrer userId is required
            if (String.isBlank(userId) || String.isBlank(lastName) || String.isBlank(primaryPhone)) {
                apexLog.response__c = 'UserId, Last Name & Primary Phone should not be blank';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('UserId, Last Name & Primary Phone should not be blank');
                return;
            }

            // Referrer = the logged-in customer
            List<Customer_Master__c> customerMasterList = [SELECT Id, Name, Customer_Name__c, Phone__c FROM Customer_Master__c WHERE Name = :userId AND isActive__c = TRUE LIMIT 1];
            if (customerMasterList.isEmpty()) {
                apexLog.response__c = 'Customer Not Found';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('Customer Not Found');
                return;
            }

            Customer_Master__c referrer = customerMasterList[0];

            Lead referralLead = new Lead();
            // Friend (the referred person) - from the form
            referralLead.FirstName = firstName;
            referralLead.LastName = lastName;
            referralLead.Phone__c = primaryPhone;
            referralLead.Secondary_phone__c = secondaryPhone;

            // Referral metadata (referrer typed on the form)
            referralLead.Referrer_Name__c = referrerName;
            referralLead.Referrer_Phone_Number__c = referrerPhone;
            referralLead.Referrer_Purpose__c = purpose;
            referralLead.Customer_Master__c = referrer.Id;

            // Mandatory referral defaults
            referralLead.Rating =  Constants.REFERRAL_RATING; // Currently 'Prospect'
            referralLead.RM_Name__c = '---';
            referralLead.Campaign_std__c = Constants.REFERRAL_CAMPAIGN_ID;
            referralLead.Sub_Campaign__c = Constants.REFERRAL_SUB_CAMPAIGN_ID;

            // Source tagging so it is clearly an app referral
            referralLead.Lead_source__c = 'Mobile App Referral';
            referralLead.Follow_up_By__c = 'Adissia One App';
            // referralLead.Sub_Source__c = 'Mobile App';
            referralLead.Description = 'Referral created via Adissia One app by ' + referrer.Name;

            // Project the referral is for -> Allocated_Project__c (resolve Project__c value from Name)
            if (String.isNotBlank(projectName)) {
                List<Project__c> projectList = [SELECT Id, Project__c FROM Project__c WHERE Name = :projectName LIMIT 1];
                if (!projectList.isEmpty()) {
                    referralLead.Allocated_Project__c = projectList[0].Project__c;
                }
            }

            // Fixed Referral Sales user (pooja@adissia.com) - owner + enquiry source
            List<User> referralOwnerList = [SELECT Id, Name FROM User WHERE Username = :REFERRAL_OWNER_USERNAME AND IsActive = TRUE LIMIT 1];
            if (!referralOwnerList.isEmpty()) {
                referralLead.OwnerId = referralOwnerList[0].Id;
                referralLead.First_Source_Of_Enquiry__c = referralOwnerList[0].Name;
                referralLead.Last_Source_Of_Enquiry__c = referralOwnerList[0].Name;
            }

            // Insert WITHOUT auto-assignment rules, so the owner stays as Pooja
            Database.DMLOptions dmlOptions = new Database.DMLOptions();
            dmlOptions.assignmentRuleHeader.useDefaultRule = false;
            referralLead.setOptions(dmlOptions);

            insert referralLead;

            // The Lead trigger reassigns owner + enquiry source during insert (round robin).
            // If this phone already belongs to an existing lead, the dedup logic DELETES the
            // lead we just inserted and merges it into that main lead - so referralLead.Id may
            // no longer exist. We therefore resolve the surviving lead by the friend's phone
            // (which is stable), then re-assert Pooja on the lead and on every enquiry source
            // still owned by the integration (Mobile API) user.
            if (!referralOwnerList.isEmpty()) {
                Id ownerId = referralOwnerList[0].Id;
                String ownerName = referralOwnerList[0].Name;
                Id runningUserId = UserInfo.getUserId();

                // Find the surviving lead(s) by the friend's phone (primary or secondary)
                Set<Id> leadIds = new Set<Id>();
                for (Lead ld : [SELECT Id FROM Lead WHERE (Phone__c = :primaryPhone OR Secondary_phone__c = :primaryPhone) AND IsConverted = FALSE]) {
                    leadIds.add(ld.Id);
                }
                // Also include the inserted lead if it still exists
                leadIds.add(referralLead.Id);

                if (!leadIds.isEmpty()) {
                    Database.DMLOptions fixOptions = new Database.DMLOptions();
                    fixOptions.assignmentRuleHeader.useDefaultRule = false;

                    // Re-assert Pooja as owner + enquiry source on the surviving lead(s)
                    List<Lead> leadsToFix = new List<Lead>();
                    for (Lead ld : [SELECT Id FROM Lead WHERE Id IN :leadIds]) {
                        Lead fix = new Lead(
                            Id = ld.Id,
                            OwnerId = ownerId,
                            First_Source_Of_Enquiry__c = ownerName,
                            Last_Source_Of_Enquiry__c = ownerName,
                            Follow_up_By__c = 'Adissia One App',
                            Lead_Assigned__c = true
                        );
                        fix.setOptions(fixOptions);
                        leadsToFix.add(fix);
                    }
                    if (!leadsToFix.isEmpty()) { update leadsToFix; }

                    // Re-own every enquiry source on those leads still owned by the integration user
                    List<Related_Source__c> enquirySources = [SELECT Id FROM Related_Source__c WHERE Lead__c IN :leadIds AND OwnerId = :runningUserId];
                    if (!enquirySources.isEmpty()) {
                        for (Related_Source__c es : enquirySources) {
                            es.OwnerId = ownerId;
                        }
                        update enquirySources;
                    }

                    // Notify Pooja (bell + email) that she is now the owner of the referral lead(s)
                    notifyNewOwner(ownerId, leadIds);
                }
            }

            apexLog.response__c = 'Referral lead created successfully by ' + userId + ' : ' + referralLead.Id;
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;

            sendSuccessResponse('Referral submitted successfully');

        } catch (Exception caughtException) {
            apexLog.response__c = caughtException.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = caughtException.getMessage();
            insert apexLog;
            sendErrorResponse('Error: ' + caughtException.getMessage());
        }
    }

    // Sends a bell notification and an email to the new lead owner (Pooja).
    // Wrapped so a notification failure never blocks lead creation.
    private static void notifyNewOwner(Id ownerId, Set<Id> leadIds) {
        if (ownerId == null || leadIds == null || leadIds.isEmpty()) { return; }
        try {
            // Bell notification via the "Lead Assignment Notification Owner Changed" type
            List<CustomNotificationType> typeList = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :OWNER_CHANGED_NOTIFICATION LIMIT 1];
            if (!typeList.isEmpty()) {
                for (Id leadId : leadIds) {
                    Messaging.CustomNotification bell = new Messaging.CustomNotification();
                    bell.setNotificationTypeId(typeList[0].Id);
                    bell.setTitle('New Referral Lead Assigned');
                    bell.setBody('A mobile app referral lead has been assigned to you.');
                    bell.setTargetId(leadId);
                    bell.setSenderId(UserInfo.getUserId());
                    if (!Test.isRunningTest()) {
                        bell.send(new Set<String>{ String.valueOf(ownerId) });
                    }
                }
            }

            // Email is sent asynchronously so Name / Lead_ID__c (stamped by automation) are
            // fully committed and populated before the email body is built.
            if (!Test.isRunningTest()) {
                Set<Id> leadIdSet = new Set<Id>(leadIds);
                sendReferralEmailAsync(ownerId, leadIdSet);
            }
        } catch (Exception notifyEx) {
            System.debug('notifyNewOwner failed: ' + notifyEx.getMessage());
        }
    }

    // Sends the owner email in a fresh transaction so the lead's auto-number (Name) and
    // Lead_ID__c are already committed and non-blank.
    @future
    private static void sendReferralEmailAsync(Id ownerId, Set<Id> leadIds) {
        try {
            List<User> ownerUserList = [SELECT Id, Email, Name FROM User WHERE Id = :ownerId LIMIT 1];
            if (ownerUserList.isEmpty() || String.isBlank(ownerUserList[0].Email)) { return; }

            List<Lead> leads = [SELECT Id, Name, Lead_ID__c FROM Lead WHERE Id IN :leadIds AND IsConverted = FALSE];
            if (leads.isEmpty()) { return; }

            List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
            for (Lead ld : leads) {
                String leadName = ld.Name != null ? ld.Name : '';
                String leadCode = ld.Lead_ID__c != null ? ld.Lead_ID__c : '';
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTargetObjectId(ownerId);
                mail.setSaveAsActivity(false);
                mail.setSubject('New Referral Lead Assigned to You' + (String.isNotBlank(leadCode) ? ' - ' + leadCode : ''));
                mail.setHtmlBody('<p>Dear ' + ownerUserList[0].Name + ',</p>' +
                    '<p>A new mobile app referral lead has been assigned to you.</p>' +
                    '<p><b>Lead Name:</b> ' + leadName + '<br/>' +
                    '<b>Lead ID:</b> ' + leadCode + '</p>' +
                    '<p>Please review it in Salesforce.</p>' +
                    '<p>Regards,<br/>Adissia System</p>');
                mails.add(mail);
            }
            if (!mails.isEmpty()) {
                Messaging.sendEmail(mails);
            }
        } catch (Exception e) {
            System.debug('sendReferralEmailAsync failed: ' + e.getMessage());
        }
    }

    public class ReferralWrapper {
        public String userId;             // referrer's AID (logged-in customer)
        public String firstName;          // friend's first name
        public String lastName;           // friend's last name (required)
        public String primaryPhone;       // friend's primary mobile (required)
        public String secondaryPhone;     // friend's secondary mobile
        public String referrerName;        // referrer's name (typed)
        public String referrerPhone;       // referrer's mobile (typed)
        public String purpose;             // referrer purpose
        public String projectName;         // project the referral is for
    }

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
        public String projectId;
    }

    public class ResponseWrapper {
        public Boolean success;
        public String message;
    }

    private static void sendSuccessResponse(String message) {
        ResponseWrapper response = new ResponseWrapper();
        response.success = true;
        response.message = message;

        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }

    private static void sendErrorResponse(String message) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        }));
    }
}


// =====================================================================================================================================


// i have one dought thta is nothing but when we have 