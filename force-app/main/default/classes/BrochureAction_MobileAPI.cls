/**
 * Author     : Sivam V
 * Class Name : BrochureAction_MobileAPI
 * API Name   : BrochureAction API
 * REST Method: POST
 * Purpose    : When a customer taps "Brochure" in the Adissia One app, re-engage
 *              their existing Lead: create a new Enquiry Source (Related_Source__c)
 *              child record against the lead, mark the lead as Re-Engaged, and
 *              allocate it to the Pre-Sales team via round robin so they call the
 *              customer. Bell + email notifications are fired to the assigned owner.
 *              Customer Id / AID is sent in the JSON body { "customerId": "AID3147" }.
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/BrochureAction/*')
global without sharing class BrochureAction_MobileAPI {

    private static final String OWNER_CHANGED_NOTIFICATION = 'Lead_Assignment_Notification_Owner_Changed';

    @HttpPost
    global static void brochureAction() {
        RestRequest request = RestContext.request;
        String requestBody = request.requestBody.toString(); // Get the JSON body
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'BrochureAction_MobileAPI';
        apexLog.Request__c = requestBody;

        try {
            BrochureWrapper requestWrapper = (BrochureWrapper) JSON.deserialize(requestBody, BrochureWrapper.class);
            String customerId = requestWrapper.customerId;

            if (String.isBlank(customerId)) {
                apexLog.response__c = 'Customer Id should not be blank';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('Customer Id should not be blank');
                return;
            }

            // Resolve the customer, then their Lead via Booking.SLead__c
            List<Customer_Master__c> customerMasterList = [SELECT Id, Name, (SELECT Id, SLead__c FROM Bookings__r WHERE SLead__c != null LIMIT 1) FROM Customer_Master__c WHERE Name = :customerId AND isActive__c = TRUE LIMIT 1];
            if (customerMasterList.isEmpty()) {
                apexLog.response__c = 'Customer Not Found';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('Customer Not Found');
                return;
            }

            Customer_Master__c customer = customerMasterList[0];
            if (customer.Bookings__r.isEmpty() || customer.Bookings__r[0].SLead__c == null) {
                apexLog.response__c = 'No lead found for this customer';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('No lead found for this customer');
                return;
            }

            Id leadId = customer.Bookings__r[0].SLead__c;

            // Load the lead (for project + phone context)
            List<Lead> leadList = [SELECT Id, Phone__c, Secondary_Phone__c, Country_Code__c, Email, Allocated_Project__c, Lead_source__c, Sub_Source__c FROM Lead WHERE Id = :leadId LIMIT 1];
            if (leadList.isEmpty()) {
                apexLog.response__c = 'Lead not found';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('Lead not found');
                return;
            }

            Lead existingLead = leadList[0];

            // A repeat brochure engagement is when a 'Mobile App' enquiry source already
            // exists on this lead (created by an earlier brochure click). The lead's original
            // creation enquiry source (Instagram/Facebook/etc) does NOT count.
            // First time (no Mobile App enquiry source yet) -> run Sales round robin.
            // Repeat (one already exists) -> keep the owner, just create + notify.
            Integer existingMobileAppSources = [SELECT COUNT() FROM Related_Source__c WHERE Lead__c = :existingLead.Id AND Source__c = 'Mobile App'];
            Boolean isRepeat = (existingMobileAppSources > 0);

            // 1) Create a new Enquiry Source (Related_Source__c) against the lead - ALWAYS
            Related_Source__c enquirySource = new Related_Source__c();
            enquirySource.Lead__c = existingLead.Id;
            enquirySource.Source__c = 'Mobile App';
            enquirySource.Phone__c = existingLead.Phone__c;
            enquirySource.Secondary_Phone__c = existingLead.Secondary_Phone__c;
            enquirySource.Country_Code__c = existingLead.Country_Code__c;
            enquirySource.Email__c = existingLead.Email;
            enquirySource.Allocated_Project__c = existingLead.Allocated_Project__c;
            enquirySource.Description__c = 'Brochure viewed via Adissia One app by ' + customer.Name;
            enquirySource.Lead_Type__c = 'Re-Engaged';
            insert enquirySource;

            // 2) Re-engage the lead. First time only -> allocate to SALES via round robin.
            //    NOTE: Lead_source__c is NEVER changed here - it is set only when the lead
            //    is first created. Re-engagement leaves the lead source untouched.
            if (!isRepeat) {
                // Ask the Sales round robin for the next owner (sets ownerId in memory)
                Lead rrLead = new Lead(Id = existingLead.Id);
                rrLead.Allocated_Project__c = existingLead.Allocated_Project__c;
                rrLead.Lead_Assigned__c = false; // allow round robin to assign
                RoundRobinHandler.assignLead(new List<Lead>{ rrLead }, false, 'Sales');
                Id rrOwnerId = rrLead.OwnerId;

                // Update the lead: re-engage + force the round-robin owner. The SLeadTrigger
                // runs on this update, so we set the owner explicitly and disable assignment
                // rules to keep the round-robin owner.
                Lead reEngageLead = new Lead(Id = existingLead.Id);
                reEngageLead.Lead_Type__c = 'Re-Engaged';
                reEngageLead.Last_Re_Engaged_Date__c = System.now();
                if (rrOwnerId != null) {
                    reEngageLead.OwnerId = rrOwnerId;
                    reEngageLead.Lead_Assigned__c = true;
                }
                Database.DMLOptions dmlOptions = new Database.DMLOptions();
                dmlOptions.assignmentRuleHeader.useDefaultRule = false;
                reEngageLead.setOptions(dmlOptions);
                update reEngageLead;

                // Re-assert the round-robin owner in case the trigger overwrote it
                if (rrOwnerId != null) {
                    Id ownerNow = [SELECT OwnerId FROM Lead WHERE Id = :existingLead.Id LIMIT 1].OwnerId;
                    if (ownerNow != rrOwnerId) {
                        Lead ownerFix = new Lead(Id = existingLead.Id, OwnerId = rrOwnerId, Lead_Assigned__c = true);
                        ownerFix.setOptions(dmlOptions);
                        update ownerFix;
                    }
                }
            } else {
                // Repeat click: keep the same owner, just mark re-engaged again.
                // Lead_source__c stays untouched.
                Lead reEngageLead = new Lead(Id = existingLead.Id);
                reEngageLead.Lead_Type__c = 'Re-Engaged';
                reEngageLead.Last_Re_Engaged_Date__c = System.now();
                update reEngageLead;
            }

            // 3) Notify the owner (bell + email) - ALWAYS, whether new or existing
            Id assignedOwnerId = [SELECT OwnerId FROM Lead WHERE Id = :existingLead.Id LIMIT 1].OwnerId;
            notifyNewOwner(assignedOwnerId, existingLead.Id);

            apexLog.response__c = 'Brochure re-engagement done for ' + customerId + ' : lead ' + existingLead.Id;
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;

            sendSuccessResponse('Brochure action recorded and lead re-engaged');

        } catch (Exception caughtException) {
            apexLog.response__c = caughtException.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = caughtException.getMessage();
            insert apexLog;
            sendErrorResponse('Error: ' + caughtException.getMessage());
        }
    }

    public class BrochureWrapper {
        public String customerId;
    }

    // Bell + email to the pre-sales owner assigned by round robin.
    private static void notifyNewOwner(Id ownerId, Id leadId) {
        if (ownerId == null || leadId == null) { return; }
        try {
            List<CustomNotificationType> typeList = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :OWNER_CHANGED_NOTIFICATION LIMIT 1];
            if (!typeList.isEmpty()) {
                Messaging.CustomNotification bell = new Messaging.CustomNotification();
                bell.setNotificationTypeId(typeList[0].Id);
                bell.setTitle('New Lead Assigned - Brochure Enquiry');
                bell.setBody('A customer viewed a brochure in the app. The lead has been assigned to you.');
                bell.setTargetId(leadId);
                bell.setSenderId(UserInfo.getUserId());
                if (!Test.isRunningTest()) {
                    bell.send(new Set<String>{ String.valueOf(ownerId) });
                }
            }

            List<User> ownerUserList = [SELECT Id, Email, Name FROM User WHERE Id = :ownerId LIMIT 1];
            if (!ownerUserList.isEmpty() && String.isNotBlank(ownerUserList[0].Email)) {
                Lead ld = [SELECT Name, Lead_ID__c FROM Lead WHERE Id = :leadId LIMIT 1];
                String leadCode = ld.Lead_ID__c != null ? ld.Lead_ID__c : '';
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTargetObjectId(ownerId);
                mail.setSaveAsActivity(false);
                mail.setSubject('New Lead Assigned - Brochure Enquiry' + (String.isNotBlank(leadCode) ? ' - ' + leadCode : ''));
                mail.setHtmlBody('<p>Dear ' + ownerUserList[0].Name + ',</p>' +
                    '<p>A customer has viewed a brochure in the Adissia One app and the lead has been assigned to you for follow-up.</p>' +
                    '<p><b>Lead Name:</b> ' + ld.Name + '<br/>' +
                    '<b>Lead ID:</b> ' + leadCode + '</p>' +
                    '<p>Please contact the customer.</p>' +
                    '<p>Regards,<br/>Adissia System</p>');
                if (!Test.isRunningTest()) {
                    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
                }
            }
        } catch (Exception notifyEx) {
            System.debug('notifyNewOwner failed: ' + notifyEx.getMessage());
        }
    }

    private static void sendSuccessResponse(String message) {
        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => true,
            'message' => message
        }));
    }

    private static void sendErrorResponse(String message) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        }));
    }
}