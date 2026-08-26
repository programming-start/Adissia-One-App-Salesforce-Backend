public without sharing class OtherPropertyNotifier {

    private static final String NOTIFICATION_TYPE_NAME = 'Build_Companion_Request_Alert';

    /**
     * Notify the Customer Delight executive (the property owner) when a customer
     * puts an Other Property up for sale. Snapshot only.
     * Never throws - notification failure must not fail the API call.
     */
    public static void notifyRequestedForSale(Id propertyId, Id ownerId) {
        if (propertyId == null || ownerId == null) {
            return;
        }
        try {
            List<Property__c> propertyList = [SELECT Id, Name, Property_Type__c, Property_Value__c, Area1__c, Area__c, Dealer_Builder_Name__c, Survay__c, Purchase_Date__c, Customer_Master__r.Name FROM Property__c WHERE Id = :propertyId LIMIT 1];
            if (propertyList.isEmpty()) {
                return;
            }
            Property__c property = propertyList[0];

            String title = 'Other Property Listed For Sale';
            String shortMessage = property.Name + ' - A customer has listed this property for sale.';

            List<String> detailLines = new List<String>{
                'Property Name : ' + property.Name,
                'Customer ID   : ' + (property.Customer_Master__r != null ? property.Customer_Master__r.Name : 'N/A'),
                'Type          : ' + property.Property_Type__c,
                'Value         : ' + String.valueOf(property.Property_Value__c),
                'Area          : ' + String.valueOf(property.Area1__c) + ' ' + property.Area__c,
                'Dealer/Builder: ' + property.Dealer_Builder_Name__c,
                'Survey No     : ' + property.Survay__c,
                'Purchase Date : ' + (property.Purchase_Date__c != null ? property.Purchase_Date__c.format() : 'N/A')
            };

            sendBellNotification(propertyId, ownerId, title, shortMessage);
            sendEmail(propertyId, ownerId, title + ' - ' + property.Name, 'A customer has listed an Other Property for sale from the Adissia One app.', detailLines);

        } catch (Exception caughtException) {
            System.debug('Other property notification failed: ' + caughtException.getMessage());
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