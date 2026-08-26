/**
 * Author  : Sivam V
 * Trigger : BuildCompanionRequestTrigger
 * Purpose : Fires the status-change webhook to the frontend whenever
 *           Build_Companion_Request__c.Status__c changes (any transition).
 * Date    : 06/07/2026
 */
trigger BuildCompanionRequestTrigger on Build_Companion_Request__c (after update) {
    List<Id> changedRequestIds = new List<Id>();
    Map<Id, String> requestIdToNewStatus = new Map<Id, String>();

    for (Build_Companion_Request__c bcr : Trigger.new) {
        Build_Companion_Request__c oldBcr = Trigger.oldMap.get(bcr.Id);
        if (bcr.Status__c != oldBcr.Status__c) {
            changedRequestIds.add(bcr.Id);
            requestIdToNewStatus.put(bcr.Id, bcr.Status__c);
        }
    }

    if (!changedRequestIds.isEmpty()) {
        BuildCompanionStatusWebhook.sendStatusWebhook(changedRequestIds, requestIdToNewStatus);
    }
}
