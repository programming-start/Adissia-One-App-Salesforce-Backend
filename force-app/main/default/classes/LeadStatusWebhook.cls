/**
 * Author     : Sivam V
 * Class Name : LeadStatusWebhook
 * Purpose    : Sends a status-change webhook to the frontend when a Lead's
 *              Lead_Status__c changes, so they can push a notification to the customer.
 *              POST {HOST}/webhooks/salesforce/lead-status
 *              Header: x-api-key
 *              Body: { "customerId": "AID2842", "status": "<Lead_Status__c>", "leadId": "Ld-xxxx" }
 *
 *              HOST + x-api-key come from the Webhook_Config__mdt 'BuildCompanion' record.
 *              Requires a Remote Site Setting for the HOST domain.
 *
 * Usage      : Called from SLeadTrigger with one line (after update context):
 *                LeadStatusWebhook.handleStatusChange(Trigger.new, Trigger.oldMap);
 * Date       : 06/07/2026
 */
public without sharing class LeadStatusWebhook {

    private static final String CONFIG_NAME = 'BuildCompanion';

    // Only app-referral leads tied to a Customer Master qualify for the webhook.
    private static final String REQUIRED_LEAD_SOURCE = 'Mobile App Referral';
    private static final String REQUIRED_FOLLOW_UP_BY = 'Adissia One App';

    // Entry point called from SLeadTrigger. Detects Lead_Status__c changes and fires the
    // webhook for those leads. Safe to call on every after-update; it no-ops if nothing changed.
    public static void handleStatusChange(List<Lead> newLeads, Map<Id, Lead> oldMap) {
        if (newLeads == null || oldMap == null) { return; }

        List<Id> changedLeadIds = new List<Id>();
        Map<Id, String> leadIdToNewStatus = new Map<Id, String>();

        for (Lead ld : newLeads) {
            Lead oldLd = oldMap.get(ld.Id);
            // Status must have changed AND the lead must be an app referral tied to a
            // Customer Master (source + follow up by + customer master all required).
            if (oldLd != null
                && ld.Lead_Status__c != oldLd.Lead_Status__c
                && ld.Lead_source__c == REQUIRED_LEAD_SOURCE
                && ld.Follow_up_By__c == REQUIRED_FOLLOW_UP_BY
                && ld.Customer_Master__c != null) {
                changedLeadIds.add(ld.Id);
                leadIdToNewStatus.put(ld.Id, ld.Lead_Status__c);
            }
        }

        if (!changedLeadIds.isEmpty()) {
            sendStatusWebhook(changedLeadIds, leadIdToNewStatus);
        }
    }

    @future(callout=true)
    public static void sendStatusWebhook(List<Id> leadIds, Map<Id, String> leadIdToNewStatus) {
        Webhook_Config__mdt config = [SELECT Host_URL__c, Api_Key__c FROM Webhook_Config__mdt WHERE DeveloperName = :CONFIG_NAME LIMIT 1];
        if (config == null || String.isBlank(config.Host_URL__c)) {
            System.debug('LeadStatusWebhook: Webhook_Config__mdt not configured, skipping.');
            return;
        }

        // Pull the customer AID + Lead_ID__c for each changed lead
        Map<Id, Lead> leadDetails = new Map<Id, Lead>([SELECT Id, Name, Lead_ID__c, Customer_Master__r.Name FROM Lead WHERE Id IN :leadIds]);

        for (Id leadId : leadIds) {
            Lead ld = leadDetails.get(leadId);
            String rawStatus = leadIdToNewStatus.get(leadId);
            if (ld == null || String.isBlank(rawStatus)) { continue; }

            String customerId = (ld.Customer_Master__r != null) ? ld.Customer_Master__r.Name : '';
            String leadCode = ld.Lead_ID__c != null ? ld.Lead_ID__c : '';

            Map<String, Object> payload = new Map<String, Object>{
                'customerId' => customerId,
                'status' => rawStatus,
                'leadId' => leadCode,
                'name' => ld.Name != null ? ld.Name : ''
            };

            try {
                HttpRequest httpRequest = new HttpRequest();
                httpRequest.setEndpoint(config.Host_URL__c + '/webhooks/salesforce/lead-status');
                httpRequest.setMethod('POST');
                httpRequest.setHeader('Content-Type', 'application/json');
                httpRequest.setHeader('x-api-key', config.Api_Key__c);
                httpRequest.setBody(JSON.serialize(payload));
                httpRequest.setTimeout(10000);

                Http http = new Http();
                HttpResponse httpResponse = http.send(httpRequest);

                Apex_Log__c apexLog = new Apex_Log__c();
                apexLog.Request_Type__c = 'LeadStatusWebhook';
                apexLog.Request__c = JSON.serialize(payload);
                apexLog.response__c = 'HTTP ' + httpResponse.getStatusCode() + ' : ' + httpResponse.getBody();
                apexLog.Status__c = (httpResponse.getStatusCode() >= 200 && httpResponse.getStatusCode() < 300) ? 'SUCCESS' : 'FAIL';
                insert apexLog;

            } catch (Exception webhookException) {
                Apex_Log__c apexLog = new Apex_Log__c();
                apexLog.Request_Type__c = 'LeadStatusWebhook';
                apexLog.Request__c = JSON.serialize(payload);
                apexLog.response__c = webhookException.getStackTraceString();
                apexLog.Status__c = 'FAIL';
                apexLog.Error_Message__c = webhookException.getMessage();
                insert apexLog;
            }
        }
    }
}