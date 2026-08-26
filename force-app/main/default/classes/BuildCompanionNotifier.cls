public without sharing class BuildCompanionNotifier {

    private static final String NOTIFICATION_TYPE_NAME = 'Build_Companion_Request_Alert';

    /**
     * Resolves the Customer Delight executive for a customer.
     * Path: Customer_Master__c -> Booking__c -> Customer_Delight__c -> OwnerId__c
     */
    public static Id getCustomerDelightOwnerId(Id customerMasterId) {
        if (customerMasterId == null) {
            return null;
        }
        List<Customer_Delight__c> customerDelightList = [SELECT Id, OwnerId__c FROM Customer_Delight__c WHERE Booking__r.Customer_Master__c = :customerMasterId AND OwnerId__c != null ORDER BY CreatedDate DESC LIMIT 1];
        return customerDelightList.isEmpty() ? null : customerDelightList[0].OwnerId__c;
    }

    /**
     * Bell notification + email for a Build Companion Request.
     */
    public static void notifyOwner(Id recordId, Id ownerId) {
        if (recordId == null || ownerId == null) {
            return;
        }
        try {
            List<Build_Companion_Request__c> requestList = [SELECT Id, Name, Request_Type__c, Guest_Name__c, Phone__c, Email__c, Project_Name__c, Other_Project_Name__c, Is_Adissia_Project__c, Customer_Master__r.Name FROM Build_Companion_Request__c WHERE Id = :recordId LIMIT 1];
            if (requestList.isEmpty()) {
                return;
            }
            Build_Companion_Request__c buildRequest = requestList[0];

            String projectName = (buildRequest.Is_Adissia_Project__c == true) ? buildRequest.Project_Name__c : buildRequest.Other_Project_Name__c;

            String title = 'New ' + buildRequest.Request_Type__c + ' Request';
            String shortMessage = buildRequest.Name + ' - You are the owner. Responsible for: ' + buildRequest.Request_Type__c;

            List<String> detailLines = new List<String>{
                'Request Number : ' + buildRequest.Name,
                'Request Type   : ' + buildRequest.Request_Type__c,
                'Customer ID    : ' + (buildRequest.Customer_Master__r != null ? buildRequest.Customer_Master__r.Name : 'N/A'),
                'Name           : ' + buildRequest.Guest_Name__c,
                'Phone          : ' + buildRequest.Phone__c,
                'Email          : ' + buildRequest.Email__c,
                'Project        : ' + (String.isBlank(projectName) ? 'N/A' : projectName)
            };

            String intro = 'You are now the owner of a new Build Companion Request raised from the Adissia One app.\n' + 'You are responsible for: ' + buildRequest.Request_Type__c;

            notify(buildRequest.Id, ownerId, title, shortMessage, title + ' - ' + buildRequest.Name, intro, detailLines);

        } catch (Exception caughtException) {
            System.debug('Build Companion notification failed: ' + caughtException.getMessage());
        }
    }

    /**
     * Bell notification + email for a Re-Sale Property record.
     */
    public static void notifyResaleOwner(Id recordId, Id ownerId) {
        if (recordId == null || ownerId == null) {
            return;
        }
        try {
            List<Re_Sale_Property__c> resaleList = [SELECT Id, Name, Description__c, Seller_Price__c, Status__c, Booking__r.Name, Customer_Master__r.Name FROM Re_Sale_Property__c WHERE Id = :recordId LIMIT 1];
            if (resaleList.isEmpty()) {
                return;
            }
            Re_Sale_Property__c resaleProperty = resaleList[0];

            String title = 'New Re-Sale Request';
            String shortMessage = resaleProperty.Name + ' - You are the owner. Responsible for: Re-Sale Property';

            List<String> detailLines = new List<String>{
                'Request Number : ' + resaleProperty.Name,
                'Customer ID    : ' + (resaleProperty.Customer_Master__r != null ? resaleProperty.Customer_Master__r.Name : 'N/A'),
                'Booking        : ' + (resaleProperty.Booking__r != null ? resaleProperty.Booking__r.Name : 'N/A'),
                'Seller Price   : ' + String.valueOf(resaleProperty.Seller_Price__c),
                'Status         : ' + resaleProperty.Status__c,
                'Description    : ' + resaleProperty.Description__c
            };

            String intro = 'You are now the owner of a new Re-Sale request raised from the Adissia One app.';

            notify(resaleProperty.Id, ownerId, title, shortMessage, title + ' - ' + resaleProperty.Name, intro, detailLines);

        } catch (Exception caughtException) {
            System.debug('Resale notification failed: ' + caughtException.getMessage());
        }
    }

    /**
     * Generic notification sender - works for any object.
     * Never throws - notification failure must not fail the API call.
     */
    private static void notify(Id recordId, Id ownerId, String title, String shortMessage, String emailSubject, String emailIntro, List<String> detailLines) {
        sendBellNotification(recordId, ownerId, title, shortMessage);
        sendEmail(recordId, ownerId, emailSubject, emailIntro, detailLines);
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

    /**
     * Notify the Customer Delight executive when a customer adds an Other Property.
     * Snapshot only - Property is the customer's private record.
     * Never throws - notification failure must not fail the API call.
     */
    public static void notifyPropertyCreated(Id propertyId, Id ownerId) {
        if (propertyId == null || ownerId == null) {
            return;
        }
        try {
            List<Property__c> propertyList = [SELECT Id, Name, Property_Type__c, Property_Value__c, Area1__c, Area__c, Dealer_Builder_Name__c, Survay__c, Purchase_Date__c, Customer_Master__r.Name FROM Property__c WHERE Id = :propertyId LIMIT 1];
            if (propertyList.isEmpty()) {
                return;
            }
            Property__c property = propertyList[0];

            String title = 'New Other Property Added';
            String shortMessage = property.Name + ' - A customer has added a new property to their portfolio.';

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
            sendEmail(propertyId, ownerId, title + ' - ' + property.Name, 'A new property has been added from the Adissia One app.', detailLines);

        } catch (Exception caughtException) {
            System.debug('Property notification failed: ' + caughtException.getMessage());
        }
    }
}