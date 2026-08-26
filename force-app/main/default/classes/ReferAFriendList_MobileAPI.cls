/**
 * Author     : Sivam V
 * Class Name : ReferAFriendList_MobileAPI
 * API Name   : ReferAFriendList API
 * REST Method: GET
 * Purpose    : Returns all Leads referred by a customer (via Customer_Master__c lookup),
 *              looked up by Customer Id / AID (?customerId=AID3147). For each referred
 *              lead it returns: name, leadStatus (Lead_Status__c), and the created date
 *              of that lead's FIRST Enquiry Source (Related_Source__c). Shown by the app
 *              as a table (referred-friends list).
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/ReferAFriendList/*')
global without sharing class ReferAFriendList_MobileAPI {

    @HttpGet
    global static void getReferredLeads() {
        RestRequest request = RestContext.request;
        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c = 'ReferAFriendList_MobileAPI';

        try {
            String customerId = request.params.get('customerId');
            log.Request__c = 'customerId=' + customerId;

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

            // All leads referred by this customer
            List<Lead> leadList = [SELECT Id, Name, Lead_Status__c FROM Lead WHERE Customer_Master__c = :cmList[0].Id ORDER BY CreatedDate DESC];

            // Earliest Enquiry Source (Related_Source__c) created date per lead
            Set<Id> leadIds = new Set<Id>();
            for (Lead ld : leadList) { leadIds.add(ld.Id); }

            Map<Id, DateTime> leadToFirstEnquiryDate = new Map<Id, DateTime>();
            if (!leadIds.isEmpty()) {
                // Ordered ascending so the FIRST one seen per lead is the earliest
                for (Related_Source__c rs : [SELECT Id, Lead__c, CreatedDate FROM Related_Source__c WHERE Lead__c IN :leadIds ORDER BY CreatedDate ASC]) {
                    if (!leadToFirstEnquiryDate.containsKey(rs.Lead__c)) {
                        leadToFirstEnquiryDate.put(rs.Lead__c, rs.CreatedDate);
                    }
                }
            }

            List<ReferredLeadData> referredLeads = new List<ReferredLeadData>();
            for (Lead ld : leadList) {
                ReferredLeadData rld = new ReferredLeadData();
                rld.name = safe(ld.Name);
                rld.leadStatus = safe(ld.Lead_Status__c);
                rld.createdDate = leadToFirstEnquiryDate.containsKey(ld.Id) ? String.valueOf(leadToFirstEnquiryDate.get(ld.Id)) : '';
                referredLeads.add(rld);
            }

            ReferredLeadResponse response = new ReferredLeadResponse();
            response.success = true;
            response.message = 'Referred leads fetched successfully';
            response.data = new ReferredLeadData_Wrapper();
            response.data.leads = referredLeads;

            log.response__c = 'Referred leads fetched for ' + customerId;
            log.Status__c = 'SUCCESS';
            insert log;

            RestContext.response.statusCode = 200;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));

        } catch (Exception e) {
            log.response__c = e.getStackTraceString();
            log.Status__c = 'FAIL';
            log.Error_Message__c = e.getMessage();
            insert log;
            sendErrorResponse('Error: ' + e.getMessage());
        }
    }

    private static String safe(String value) {
        return value == null ? '' : value;
    }

    // --------------------------------------------------------------- WRAPPERS
    public class ReferredLeadResponse {
        public Boolean success;
        public String message;
        public ReferredLeadData_Wrapper data;
    }
    public class ReferredLeadData_Wrapper {
        public List<ReferredLeadData> leads;
    }
    public class ReferredLeadData {
        public String name;
        public String leadStatus;
        public String createdDate;
    }

    private static void sendErrorResponse(String message) {
        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'success' => false,
            'message' => message
        }));
    }
}