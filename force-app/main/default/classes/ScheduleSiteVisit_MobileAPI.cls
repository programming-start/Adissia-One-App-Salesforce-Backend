/*
FIRST-TIME (no scheduled/rescheduled SV exists):

Create the site visit.
Round robin → assign Sales owner, change lead owner, notify.

REPEAT (scheduled/rescheduled SV exists):

No new site visit — instead create the enquiry source (Related_Source__c) directly.
Owner availability check:
Owner still active Sales RR member → keep them, notify only.
Not available → round robin new Sales owner + change lead owner + notify.


*/

@RestResource(urlMapping='/ScheduleSiteVisitAPI/*')
global without sharing class ScheduleSiteVisit_MobileAPI {


    @HttpPost
    global static void createSiteVisit() {
        RestRequest req = RestContext.request;
        String requestBody = req.requestBody.toString(); // Get the JSON body
        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c ='ScheduleSiteVisit_MobileAPI';
        log.Request__c = requestBody;
        try{
            SiteVisitDataWrapper proj = (SiteVisitDataWrapper) JSON.deserialize(requestBody, SiteVisitDataWrapper.class);
            String userId = proj.userId;
            String projectId = proj.projectId;
            String firstName = proj.firstName;
            String lastName = proj.lastName;
            String email = proj.email;
            String phoneNumber = proj.phoneNumber;
            DateTime svdate = proj.svdate;

            if (String.isBlank(userId) ||String.isBlank(projectId) || String.isBlank(lastName)|| String.isBlank(phoneNumber) ) {
                log.response__c = 'Site Visit Data should not be blank';
                log.Status__c ='SUCCESS';
                insert log;
                sendErrorResponse('Site Visit Data should not be blank');
                return;
            }
            List<Customer_Master__c> cmList = [ SELECT Id, Email__c, Password__c, First_Name__c, Last_Name__c, Phone__c,Name, (SELECT Id, SLead__c, Contact_Number__c, Mobile_Alternate__c, Contact_Number1__c, Mobile_Alternate1__c FROM Bookings__r WHERE SLead__c != null) FROM Customer_Master__c WHERE Name = :userId AND isActive__c = TRUE LIMIT 1 ];

            if (cmList.isEmpty()) {
                log.response__c = 'Customer Not Found';
                log.Status__c ='SUCCESS';
                insert log;
                sendErrorResponse('Customer Not Found');
                return;
            }
            Set <String> PhoneSet = new Set<String>();
            Set <String> mailSet = new Set<String>();

            List<Project__c> project = [ SELECT Id, Name, Project__c FROM Project__c WHERE Name = :projectId LIMIT 1  ];

            if (project.isEmpty()) {
                log.response__c = 'Project Not Found';
                log.Status__c = 'SUCCESS';
                insert log;
                sendErrorResponse('Project Not Found');
                return;
            }

            string SaleRecTyp = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Sales').getRecordTypeId();
            string PreSaleRecTyp = Schema.SObjectType.Lead.getRecordTypeInfosByName().get('Pre Sales').getRecordTypeId();

            List<Lead> Leadlst = new List<Lead>();
            if(!cmList[0].Bookings__r.isEmpty()){
                // Pick the booking whose applicant phone matches the phone sent, so the
                // correct person's lead is used (a customer master can hold multiple
                // bookings for different applicants). Fall back to the first booking.
                Id matchedLeadId = null;
                for(Booking__c bk : cmList[0].Bookings__r){
                    if(bk.Contact_Number__c == phoneNumber || bk.Mobile_Alternate__c == phoneNumber
                        || bk.Contact_Number1__c == phoneNumber || bk.Mobile_Alternate1__c == phoneNumber){
                        matchedLeadId = bk.SLead__c;
                        break;
                    }
                }
                if(matchedLeadId == null){
                    matchedLeadId = cmList[0].Bookings__r[0].SLead__c;
                }
                Leadlst = [SELECT Id,Email,Phone__c,Phone,Secondary_phone__c,Tertiary_Phone__c,RecordTypeId,PhoneProject__c,Secondary_Phone_Project__c,
                                          SecondaryEmailProject__c,EmailProject__c,Secondary_Email__c,OwnerId,
                                          Allocated_Project__c FROM Lead WHERE Id =: matchedLeadId limit 1];
            }

            if(Leadlst.isEmpty()){
                Leadlst = [SELECT Id,Email,RecordTypeId,Phone__c,PhoneProject__c,Secondary_Phone_Project__c,
                                          SecondaryEmailProject__c,EmailProject__c,Secondary_phone__c,Secondary_Email__c,Tertiary_Phone__c,OwnerId,
                                          Allocated_Project__c FROM Lead WHERE (Phone__c =: phoneNumber OR Secondary_phone__c =:phoneNumber OR Tertiary_Phone__c =: phoneNumber)
                                          AND Lead_Status__c!='Abandoned' ORDER BY CreatedDate ASC limit 1];
            }

            if(!Leadlst.isEmpty()){
                try {

                    // REPEAT booking: a scheduled/rescheduled SV already exists for this lead.
                    // REPEAT: a scheduled/rescheduled SV already exists. Do NOT create a new
                    // site visit - create a new Enquiry Source (Related_Source__c) instead, and
                    // run the owner availability check: keep + notify if the owner is still an
                    // active Sales RR member, otherwise round robin a new owner + notify.
                    List<Site_Visit__c> sv = [SELECT Status__c,Lead__c, Project__c FROM Site_Visit__c WHERE Lead__c =: Leadlst[0].Id and (Status__c = 'Scheduled' or Status__c = 'Rescheduled')];
                    if(!sv.isEmpty()){
                        Boolean ownerStillAvailable = isActiveSalesRRMember(Leadlst[0].OwnerId, project[0].Project__c);

                        // Create the enquiry source against the lead (re-engagement)
                        Related_Source__c enquirySource = new Related_Source__c();
                        enquirySource.Lead__c = Leadlst[0].Id;
                        enquirySource.Source__c = 'Mobile App';
                        enquirySource.Phone__c = Leadlst[0].Phone__c;
                        enquirySource.Secondary_Phone__c = Leadlst[0].Secondary_phone__c;
                        enquirySource.Email__c = Leadlst[0].Email;
                        enquirySource.Allocated_Project__c = project[0].Project__c;
                        enquirySource.Description__c = 'SV re-engagement via Adissia One app by ' + cmList[0].Name;
                        enquirySource.Lead_Type__c = 'Re-Engaged';

                        if(ownerStillAvailable){
                            // Owner still active -> keep them, notify only
                            insert enquirySource;
                            notifySiteVisitOwner(Leadlst[0].OwnerId, Leadlst[0].Id, null);

                            log.response__c = 'Repeat booking: enquiry source created, existing owner retained for ' + userId;
                            log.Status__c = 'SUCCESS';
                            insert log;
                        } else {
                            // Owner no longer available -> round robin a new Sales owner for the lead
                            Lead rrLead = new Lead(Id = Leadlst[0].Id);
                            rrLead.Allocated_Project__c = project[0].Project__c;
                            rrLead.Lead_Assigned__c = false;
                            RoundRobinHandler.assignLead(new List<Lead>{ rrLead }, false, 'Sales');
                            Id newOwnerId = rrLead.OwnerId;

                            insert enquirySource;

                            if(newOwnerId != null){
                                Lead ownerFix = new Lead(Id = Leadlst[0].Id, OwnerId = newOwnerId, Lead_Assigned__c = true);
                                Database.DMLOptions dmlo = new Database.DMLOptions();
                                dmlo.assignmentRuleHeader.useDefaultRule = false;
                                ownerFix.setOptions(dmlo);
                                update ownerFix;
                            }
                            notifySiteVisitOwner(newOwnerId, Leadlst[0].Id, null);

                            log.response__c = 'Repeat booking: enquiry source created, owner reassigned via round robin for ' + userId;
                            log.Status__c = 'SUCCESS';
                            insert log;
                        }

                        sendSuccessResponse();
                        return;
                    }

                    // Site Visit owner must be a SALES user assigned via the Sales round robin
                    // for this project (not the site-visit user).
                    if (!Leadlst.isEmpty() && !project.isEmpty() &&
                        Leadlst[0].RecordTypeId == SaleRecTyp) {

                            Site_Visit__c svRec = new Site_Visit__c(
                                Lead__c   = Leadlst[0].Id,
                                Date__c   = svdate,
                                Project__c = project[0].Project__c,
                                Customer_Master__c = cmList[0].Id,
                                IsFromUpdateLdStat__c = true
                            );

                            // FIRST TIME: assign a SALES user to the Site Visit via round robin,
                            // then move the lead's owner to that same Sales person + notify.
                            RoundRobinHandler.SiteVisitAssignment(new List<Site_Visit__c>{ svRec }, 'Sales');

                            insert svRec;

                            if(svRec.OwnerId != null){
                                Lead ownerFix = new Lead(Id = Leadlst[0].Id, OwnerId = svRec.OwnerId, Lead_Assigned__c = true);
                                Database.DMLOptions dmlo = new Database.DMLOptions();
                                dmlo.assignmentRuleHeader.useDefaultRule = false;
                                ownerFix.setOptions(dmlo);
                                update ownerFix;
                            }
                            notifySiteVisitOwner(svRec.OwnerId, Leadlst[0].Id, svRec.Id);

                            log.response__c = 'Site Visit Created Successfully by ' + userId;
                            log.Status__c   = 'SUCCESS';
                            insert log;

                            sendSuccessResponse();
                            return;
                        }

                    else{
                        lead ld = new lead();
                        ld.Id = Leadlst[0].Id;
                        ld.Status = 'Site Visit Scheduled';
                        ld.Allocated_Project__c = project[0].Project__c;
                        update ld;

                        Site_Visit__c svRec = new Site_Visit__c();
                        svRec.Lead__c = ld.Id;
                        svRec.Date__c = svdate;
                        svRec.Project__c = project[0].Project__c;
                        svRec.IsFromUpdateLdStat__c = true;
                        svRec.Customer_Master__c = cmList[0].Id;

                        // Assign a SALES user to the Site Visit via round robin,
                        // then move the lead owner to that Sales person + notify.
                        RoundRobinHandler.SiteVisitAssignment(new List<Site_Visit__c>{ svRec }, 'Sales');

                        insert svRec;

                        if(svRec.OwnerId != null){
                            Lead ownerFix = new Lead(Id = ld.Id, OwnerId = svRec.OwnerId, Lead_Assigned__c = true);
                            Database.DMLOptions dmlo = new Database.DMLOptions();
                            dmlo.assignmentRuleHeader.useDefaultRule = false;
                            ownerFix.setOptions(dmlo);
                            update ownerFix;
                        }
                        notifySiteVisitOwner(svRec.OwnerId, ld.Id, svRec.Id);

                        // Log entry
                        log.response__c = 'Site Visit Created Successfully by ' + userId;
                        log.Status__c = 'SUCCESS';
                        insert log;

                        // Send success back to integration
                        sendSuccessResponse();
                        return;
                    }

                }
                catch (Exception e) {

                    String rawMsg = e.getMessage();
                    String cleanMsg = rawMsg;

                    // Remove unwanted Salesforce prefix text
                    if (rawMsg.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION')) {
                        cleanMsg = rawMsg.substringAfter('FIELD_CUSTOM_VALIDATION_EXCEPTION,');
                        cleanMsg = cleanMsg.replace(': []', '').trim();
                    }

                    // Log the error
                    log.response__c = cleanMsg;
                    log.Status__c = 'ERROR';
                    insert log;

                    // Send UI friendly message
                    sendErrorResponse(cleanMsg);
                }

            }
            else{
                Lead ld = new Lead();
                ld.LastName = lastName;
                ld.Allocated_Project__c = project[0].Project__c;
                ld.Phone= phoneNumber;
                ld.Email =email;
                ld.Lead_source__c ='Mobile App';
                ld.Sub_Source__c = 'Created By '+ cmList[0].Name;
                insert ld;

                Site_Visit__c sv = new Site_Visit__c();
                sv.Lead__c = ld.id;
                sv.Date__c =svdate;
                sv.Project__c = project[0].Project__c;
                sv.Customer_Master__c = cmList[0].Id;

                // Assign a SALES user to the Site Visit via round robin,
                // then move the lead owner to that Sales person + notify.
                RoundRobinHandler.SiteVisitAssignment(new List<Site_Visit__c>{ sv }, 'Sales');

                insert sv;

                if(sv.OwnerId != null){
                    Lead ownerFix = new Lead(Id = ld.Id, OwnerId = sv.OwnerId, Lead_Assigned__c = true);
                    Database.DMLOptions dmlo = new Database.DMLOptions();
                    dmlo.assignmentRuleHeader.useDefaultRule = false;
                    ownerFix.setOptions(dmlo);
                    update ownerFix;
                }
                notifySiteVisitOwner(sv.OwnerId, ld.Id, sv.Id);

                log.response__c = 'Lead and Site Visit Created Successfully by ' + userId;
                log.Status__c = 'SUCCESS';
                insert log;

                sendSuccessResponse();
            }

        }
        Catch (Exception e){
            log.response__c = e.getStackTraceString();
            log.Status__c ='FAIL';
            log.Error_Message__c = e.getMessage();
            insert log;
            sendErrorResponse('Error: ' + e.getMessage());


        }
    }


    // True if the given user is an ACTIVE Sales round-robin member for the project
    // (member Active + user IsActive + working). Used to decide whether to keep the
    // existing owner on a repeat booking or reassign via round robin.
    private static Boolean isActiveSalesRRMember(Id ownerId, String projectValue){
        if(ownerId == null || String.isBlank(projectValue)){ return false; }
        Integer cnt = [SELECT COUNT() FROM Round_Robin_Member__c
                       WHERE User__c = :ownerId
                         AND User_Type__c = 'Sales'
                         AND Active__c = true
                         AND User__r.IsActive = true
                         AND User__r.is_working__c = true
                         AND Round_Robin__r.Project_Assigned__c = :projectValue
                         AND Round_Robin__r.Active__c = true];
        return cnt > 0;
    }

    // Bell + email to the site visit owner (Sales person).
    private static void notifySiteVisitOwner(Id ownerId, Id leadId, Id siteVisitId){
        if(ownerId == null){ return; }
        try {
            List<CustomNotificationType> typeList = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Lead_Assignment_Notification_Owner_Changed' LIMIT 1];
            if(!typeList.isEmpty()){
                Messaging.CustomNotification bell = new Messaging.CustomNotification();
                bell.setNotificationTypeId(typeList[0].Id);
                bell.setTitle('New Site Visit Assigned');
                bell.setBody('A site visit has been booked from the mobile app and assigned to you.');
                bell.setTargetId(leadId != null ? leadId : siteVisitId);
                bell.setSenderId(UserInfo.getUserId());
                if(!Test.isRunningTest()){
                    bell.send(new Set<String>{ String.valueOf(ownerId) });
                }
            }
            List<User> ownerUserList = [SELECT Id, Email, Name FROM User WHERE Id = :ownerId LIMIT 1];
            if(!ownerUserList.isEmpty() && String.isNotBlank(ownerUserList[0].Email)){
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setTargetObjectId(ownerId);
                mail.setSaveAsActivity(false);
                mail.setSubject('New Site Visit Assigned to You');
                mail.setHtmlBody('<p>Dear ' + ownerUserList[0].Name + ',</p>' +
                    '<p>A site visit has been booked from the Adissia One app and assigned to you. Please review it in Salesforce.</p>' +
                    '<p>Regards,<br/>Adissia System</p>');
                if(!Test.isRunningTest()){
                    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
                }
            }
        } catch(Exception notifyEx){
            System.debug('notifySiteVisitOwner failed: ' + notifyEx.getMessage());
        }
    }

    public class SiteVisitDataWrapper {
        public String userId;
        public String projectId;
        public String firstName;
        public String lastName;
        public String email;
        public String phoneNumber;
        public DateTime svdate;

    }

    private static void sendErrorResponse(String message) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
                'message' => message
                }));
    }
    public class ResponseWrapper {
        public Boolean success;
        public String message;
    }
    private static void sendSuccessResponse() {
        ResponseWrapper response = new ResponseWrapper();
        response.success = true;
        response.message = 'Site Visit Booked Successfully';

        RestResponse res = RestContext.response;
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(response));
    }

}