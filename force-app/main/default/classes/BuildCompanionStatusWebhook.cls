/**
 * Class Name : BuildCompanionStatusWebhook
 * Purpose    : Sends a status-change webhook to the frontend team's endpoint whenever a
 *              Build_Companion_Request__c's Status__c changes, so they can push a
 *              notification to the customer.
 *              POST {HOST}/webhooks/salesforce/request-status
 *              Header: x-api-key
 *              Body: { "requestId": "BCR-000124", "status": "Progress" }
 *
 *              HOST + x-api-key are read from the Webhook_Config__mdt Custom Metadata
 *              record labelled 'BuildCompanion' - update the values there, no code change
 *              needed. Requires a Remote Site Setting for the HOST domain.
 * Date       : 06/07/2026Author     : Sivam V
 * 
 */
public without sharing class BuildCompanionStatusWebhook {

    private static final String CONFIG_NAME = 'BuildCompanion';

    // Maps the full picklist value to the short code the frontend expects
    // Org picklist values are already Pending / Progress / Completed - sent as-is.
    // Map kept for any future re-labelling; unmatched values fall through unchanged.
    private static final Map<String, String> STATUS_CODE_MAP = new Map<String, String>{
        'Pending' => 'Pending',
        'Progress' => 'Progress',
        'Completed' => 'Completed'
    };

    @future(callout=true)
    public static void sendStatusWebhook(List<Id> requestIds, Map<Id, String> requestIdToNewStatus) {
        Webhook_Config__mdt config = [SELECT Host_URL__c, Api_Key__c FROM Webhook_Config__mdt WHERE DeveloperName = :CONFIG_NAME LIMIT 1];
        if (config == null || String.isBlank(config.Host_URL__c)) {
            System.debug('BuildCompanionStatusWebhook: Webhook_Config__mdt not configured, skipping.');
            return;
        }

        Map<Id, String> requestIdToName = new Map<Id, String>();
        Map<Id, String> requestIdToCustomer = new Map<Id, String>();
        for (Build_Companion_Request__c bcr : [SELECT Id, Name, Customer_Master__r.Name FROM Build_Companion_Request__c WHERE Id IN :requestIds]) {
            requestIdToName.put(bcr.Id, bcr.Name);
            requestIdToCustomer.put(bcr.Id, bcr.Customer_Master__r != null ? bcr.Customer_Master__r.Name : '');
        }

        for (Id recId : requestIds) {
            String requestNumber = requestIdToName.get(recId);
            String rawStatus = requestIdToNewStatus.get(recId);
            if (String.isBlank(requestNumber) || String.isBlank(rawStatus)) { continue; }

            String statusCode = STATUS_CODE_MAP.containsKey(rawStatus) ? STATUS_CODE_MAP.get(rawStatus) : rawStatus;

            String customerId = requestIdToCustomer.get(recId);

            Map<String, Object> payload = new Map<String, Object>{
                'requestId' => requestNumber,
                'status' => statusCode,
                'customerId' => customerId
            };

            try {
                HttpRequest httpRequest = new HttpRequest();
                httpRequest.setEndpoint(config.Host_URL__c + '/webhooks/salesforce/request-status');
                httpRequest.setMethod('POST');
                httpRequest.setHeader('Content-Type', 'application/json');
                httpRequest.setHeader('x-api-key', config.Api_Key__c);
                httpRequest.setBody(JSON.serialize(payload));
                httpRequest.setTimeout(10000);

                Http http = new Http();
                HttpResponse httpResponse = http.send(httpRequest);

                System.debug('BuildCompanionStatusWebhook: ' + requestNumber + ' -> ' + statusCode + ' | HTTP ' + httpResponse.getStatusCode());

                Apex_Log__c apexLog = new Apex_Log__c();
                apexLog.Request_Type__c = 'BuildCompanionStatusWebhook';
                apexLog.Request__c = JSON.serialize(payload);
                apexLog.response__c = 'HTTP ' + httpResponse.getStatusCode() + ' : ' + httpResponse.getBody();
                apexLog.Status__c = (httpResponse.getStatusCode() >= 200 && httpResponse.getStatusCode() < 300) ? 'SUCCESS' : 'FAIL';
                insert apexLog;

            } catch (Exception webhookException) {
                Apex_Log__c apexLog = new Apex_Log__c();
                apexLog.Request_Type__c = 'BuildCompanionStatusWebhook';
                apexLog.Request__c = JSON.serialize(payload);
                apexLog.response__c = webhookException.getStackTraceString();
                apexLog.Status__c = 'FAIL';
                apexLog.Error_Message__c = webhookException.getMessage();
                insert apexLog;
            }
        }
    }
}



