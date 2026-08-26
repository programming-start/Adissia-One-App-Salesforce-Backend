public without sharing class ReSaleNotifier {

    private static final String NOTIFICATION_TYPE_NAME = 'Build_Companion_Request_Alert';
    private static final String OWNER_PROFILE_NAME = 'Customer Delights';

    private static Id cachedOwnerId;
    private static Boolean ownerResolved = false;

    /**
     * Returns the active user on the Customer Delights profile.
     * No hardcoded Id - works the same in sandbox and production.
     */
    public static Id getResaleOwnerId() {
        if (ownerResolved) {
            return cachedOwnerId;
        }
        ownerResolved = true;
        List<User> customerDelightsUsers = [SELECT Id FROM User WHERE Profile.Name = :OWNER_PROFILE_NAME AND IsActive = TRUE ORDER BY CreatedDate ASC LIMIT 1];
        cachedOwnerId = customerDelightsUsers.isEmpty() ? null : customerDelightsUsers[0].Id;
        return cachedOwnerId;
    }

    /**
     * Notify on new re-sale listing.
     */
    public static void notifyCreated(Id recordId, Id ownerId) {
        notifyResale(recordId, ownerId, 'New Re-Sale Request', 'A new Re-Sale listing has been raised from the Adissia One app.');
    }

    /**
     * Notify on re-sale listing edit.
     * changedFieldLines holds one entry per changed field, already formatted as
     * "Field : previous value -> current value".
     */
    public static void notifyUpdated(Id recordId, Id ownerId, List<String> changedFieldLines) {
        if (recordId == null || ownerId == null || changedFieldLines == null || changedFieldLines.isEmpty()) {
            return;
        }
        try {
            List<Re_Sale_Property__c> resaleList = [SELECT Id, Name, Booking__r.Name, Customer_Master__r.Name FROM Re_Sale_Property__c WHERE Id = :recordId LIMIT 1];
            if (resaleList.isEmpty()) {
                return;
            }
            Re_Sale_Property__c resaleProperty = resaleList[0];

            String title = 'Re-Sale Request Updated';
            String shortMessage = resaleProperty.Name + ' - The customer has edited this listing. It is back for your approval.';

            List<String> detailLines = new List<String>{
                'Request Number : ' + resaleProperty.Name,
                'Customer ID    : ' + (resaleProperty.Customer_Master__r != null ? resaleProperty.Customer_Master__r.Name : 'N/A'),
                'Booking        : ' + (resaleProperty.Booking__r != null ? resaleProperty.Booking__r.Name : 'N/A'),
                '',
                'Changes made by the customer :',
                ''
            };
            detailLines.addAll(changedFieldLines);

            sendBellNotification(resaleProperty.Id, ownerId, title, shortMessage);
            sendEmail(resaleProperty.Id, ownerId, title + ' - ' + resaleProperty.Name, 'A Re-Sale listing has been edited from the Adissia One app.', detailLines);

        } catch (Exception caughtException) {
            System.debug('Resale update notification failed: ' + caughtException.getMessage());
        }
    }

    /**
     * Notify on re-sale cancellation request.
     * The record is not deleted - only the status moves to Requested for Cancellation.
     * Call this AFTER the status update, so the snapshot shows the new status.
     */
    public static void notifyDeleted(Id recordId, Id ownerId) {
        notifyResale(recordId, ownerId, 'Re-Sale Cancellation Requested', 'A Re-Sale cancellation has been requested from the Adissia One app.');
    }

    /**
     * Shared re-sale notification builder.
     * Never throws - notification failure must not fail the API call.
     */
    private static void notifyResale(Id recordId, Id ownerId, String title, String emailIntro) {
        if (recordId == null || ownerId == null) {
            return;
        }
        try {
            List<Re_Sale_Property__c> resaleList = [SELECT Id, Name, Description__c, Seller_Price__c, Status__c, Booking__r.Name, Customer_Master__r.Name FROM Re_Sale_Property__c WHERE Id = :recordId LIMIT 1];
            if (resaleList.isEmpty()) {
                return;
            }
            Re_Sale_Property__c resaleProperty = resaleList[0];

            String shortMessage = resaleProperty.Name + ' - You are the owner. Responsible for: Re-Sale Property';

            List<String> detailLines = new List<String>{
                'Request Number : ' + resaleProperty.Name,
                'Customer ID    : ' + (resaleProperty.Customer_Master__r != null ? resaleProperty.Customer_Master__r.Name : 'N/A'),
                'Booking        : ' + (resaleProperty.Booking__r != null ? resaleProperty.Booking__r.Name : 'N/A'),
                'Seller Price   : ' + String.valueOf(resaleProperty.Seller_Price__c),
                'Status         : ' + resaleProperty.Status__c,
                'Description    : ' + resaleProperty.Description__c
            };

            sendBellNotification(resaleProperty.Id, ownerId, title, shortMessage);
            sendEmail(resaleProperty.Id, ownerId, title + ' - ' + resaleProperty.Name, emailIntro, detailLines);

        } catch (Exception caughtException) {
            System.debug('Resale notification failed: ' + caughtException.getMessage());
        }
    }

    private static void sendBellNotification(Id recordId, Id ownerId, String title, String shortMessage) {
        try {
            List<CustomNotificationType> notificationTypeList = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE_NAME LIMIT 1];
            if (notificationTypeList.isEmpty()) {
                return;
            }
            Messaging.CustomNotification customNotification = new Messaging.CustomNotification();
            customNotification.setNotificationTypeId(notificationTypeList[0].Id);
            customNotification.setTargetId(recordId);
            customNotification.setTitle(title);
            customNotification.setBody(shortMessage);
            customNotification.send(new Set<String>{ String.valueOf(ownerId) });

        } catch (Exception caughtException) {
            System.debug('Bell notification failed: ' + caughtException.getMessage());
        }
    }

    private static void sendEmail(Id recordId, Id ownerId, String emailSubject, String emailIntro, List<String> detailLines) {
        try {
            List<User> ownerList = [SELECT Id, Name, Email FROM User WHERE Id = :ownerId AND IsActive = TRUE LIMIT 1];
            if (ownerList.isEmpty() || String.isBlank(ownerList[0].Email)) {
                return;
            }

            String baseUrl = URL.getOrgDomainUrl().toExternalForm();

            String emailBody = 'Hi ' + ownerList[0].Name + ',\n\n' + emailIntro + '\n\n' + String.join(detailLines, '\n') + '\n\n' + 'Open the record: ' + baseUrl + '/' + recordId + '\n\n' + 'Regards,\nAdissia Salesforce';

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ ownerList[0].Email });
            email.setSubject(emailSubject);
            email.setPlainTextBody(emailBody);
            email.setSaveAsActivity(false);

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);

        } catch (Exception caughtException) {
            System.debug('Email failed: ' + caughtException.getMessage());
        }
    }
}