/**
 * Author     : Sivam V
 * Class Name : OtherProperty_MobileAPI
 * API Name   : OtherProperty API
 * REST Method: GET & POST
 * Purpose    : "Other Property" section (private to each customer).
 *   GET  ?type=form        -> form definition (fields to render)
 *   POST { action, ... }   -> create / edit / delete / list (customer's own only)
 * Notes:
 *   - Notification fires ONLY on create. Edit / delete send nothing.
 *   - Delete is a SOFT delete: Status__c = 'Deleted' (list excludes these).
 *   - Every create / edit / delete returns the auto-number Name__c (OP-xxx) in requestId.
 *   - No public "For Sale" browse - a customer only ever sees their own properties.
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/OtherPropertyAPI/*')
global without sharing class OtherProperty_MobileAPI {

    private static final List<String> PROPERTY_TYPES = new List<String>{ 'Villa', 'Flat', 'Open Plot' };
    private static final List<String> AREA_TYPES = new List<String>{ 'Sq.ft', 'Sq.mt', 'Cents' };

    // =============================================================== GET (form)
    @HttpGet
    global static void getForm() {
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'OtherPropertyAPI';
        apexLog.Request__c = 'GET other property form';

        try {
            List<FieldOption> propertyTypeOptions = new List<FieldOption>();
            for (String pt : PROPERTY_TYPES) {
                FieldOption option = new FieldOption();
                option.label = pt;
                option.value = pt;
                propertyTypeOptions.add(option);
            }
            List<FieldOption> areaTypeOptions = new List<FieldOption>();
            for (String at : AREA_TYPES) {
                FieldOption option = new FieldOption();
                option.label = at;
                option.value = at;
                areaTypeOptions.add(option);
            }

            List<FormField> fields = new List<FormField>();
            fields.add(makeField('propertyName', 'Property Name', 'text', true));
            fields.add(makeSelectField('propertyType', 'Property Type', 'select', true, propertyTypeOptions));
            fields.add(makeField('propertyValue', 'Property Value', 'number', true));
            fields.add(makeSelectField('areaType', 'Area Type', 'select', true, areaTypeOptions));
            fields.add(makeField('area', 'Area', 'number', true));
            fields.add(makeField('dealerName', 'Dealer / Builder Name', 'text', true));
            fields.add(makeField('surveyNo', 'Survey No', 'text', false));
            fields.add(makeField('purchaseDate', 'Purchase Date', 'date', false));

            FormResponse response = new FormResponse();
            response.success = true;
            response.message = 'Other property form fetched successfully';
            response.data = new FormData();
            response.data.formTitle = 'Add Other Property';
            response.data.submitEndpoint = '/services/apexrest/OtherPropertyAPI';
            response.data.submitMethod = 'POST';
            response.data.fields = fields;

            apexLog.response__c = 'Form fetched successfully';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;

            RestContext.response.statusCode = 200;
            RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));

        } catch (Exception e) {
            apexLog.response__c = e.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = e.getMessage();
            insert apexLog;
            sendErrorResponse('Error: ' + e.getMessage());
        }
    }

    // =============================================================== POST (actions)
    @HttpPost
    global static void handlePropertyRequest() {
        RestRequest request = RestContext.request;
        String requestBody = request.requestBody.toString(); // Get the JSON body
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'OtherPropertyAPI';
        apexLog.Request__c = requestBody;

        try {
            PropertyWrapper requestWrapper = (PropertyWrapper) JSON.deserialize(requestBody, PropertyWrapper.class);
            String action = requestWrapper.action;

            if (String.isBlank(action)) {
                apexLog.response__c = 'action should not be blank';
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('action should not be blank');
                return;
            }

            if (action == 'create') {
                handleCreate(requestWrapper, apexLog);
            } else if (action == 'edit') {
                handleEdit(requestWrapper, apexLog);
            } else if (action == 'delete') {
                handleDelete(requestWrapper, apexLog);
            } else if (action == 'list') {
                handleList(requestWrapper, apexLog);
            } else if (action == 'uploadImage') {
                handleUploadImage(requestWrapper, apexLog);
            } else if (action == 'deleteImage') {
                handleDeleteImage(requestWrapper, apexLog);
            } else {
                apexLog.response__c = 'Invalid action : ' + action;
                apexLog.Status__c = 'SUCCESS';
                insert apexLog;
                sendErrorResponse('Invalid action : ' + action);
            }

        } catch (Exception caughtException) {
            apexLog.response__c = caughtException.getStackTraceString();
            apexLog.Status__c = 'FAIL';
            apexLog.Error_Message__c = caughtException.getMessage();
            insert apexLog;
            sendErrorResponse('Error: ' + caughtException.getMessage());
        }
    }

    // ---------------------------------------------------------------- CREATE
    // Saved as Private. Owner = the customer's Customer Delight executive.
    // Notification fires here (create only). Returns the OP-xxx number.
    private static void handleCreate(PropertyWrapper requestWrapper, Apex_Log__c apexLog) {
        String userId = requestWrapper.userId;

        if (String.isBlank(userId) || String.isBlank(requestWrapper.propertyName) || String.isBlank(requestWrapper.propertyValue) || String.isBlank(requestWrapper.area) || String.isBlank(requestWrapper.dealerName)) {
            apexLog.response__c = 'UserId or Property Data should not be blank';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('UserId or Property Data should not be blank');
            return;
        }

        List<Customer_Master__c> customerMasterList = [SELECT Id, Name FROM Customer_Master__c WHERE Name = :userId AND isActive__c = TRUE LIMIT 1];
        if (customerMasterList.isEmpty()) {
            apexLog.response__c = 'Customer Not Found';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Customer Not Found');
            return;
        }

        Property__c property = new Property__c();
        property.Name = requestWrapper.propertyName;
        property.Property_Type__c = requestWrapper.propertyType;
        property.Property_Value__c = Decimal.valueOf(requestWrapper.propertyValue);
        property.Area__c = requestWrapper.areaType;
        property.Area1__c = Decimal.valueOf(requestWrapper.area);
        property.Dealer_Builder_Name__c = requestWrapper.dealerName;
        property.Survay__c = requestWrapper.surveyNo;
        property.Purchase_Date__c = requestWrapper.purchaseDate;
        property.Customer_Master__c = customerMasterList[0].Id;
        property.Status__c = 'Private';

        // Owner = the owner of the customer's Customer Delight record (created at
        // booking -> registration). Resolved via the customer's booking. The Created By
        // stays as the running integration user (Mobile API User) automatically.
        Id cdOwnerId = getCustomerDelightRecordOwner(customerMasterList[0].Id);
        if (cdOwnerId == null) {
            // Fallback to the existing CD owner resolver if no CD record is found
            cdOwnerId = BuildCompanionNotifier.getCustomerDelightOwnerId(customerMasterList[0].Id);
        }
        if (cdOwnerId != null) {
            property.OwnerId = cdOwnerId;
        }

        insert property;

        // Notification ONLY on create
        OtherPropertyNotifier.notifyRequestedForSale(property.Id, cdOwnerId);

        Property__c created = [SELECT Name__c FROM Property__c WHERE Id = :property.Id LIMIT 1];

        apexLog.response__c = 'Property added successfully ' + created.Name__c;
        apexLog.Status__c = 'SUCCESS';
        insert apexLog;

        sendActionResponse('Property added successfully', created.Name__c, property.Name, '');
    }

    // ------------------------------------------------------------------ EDIT (no notification)
    private static void handleEdit(PropertyWrapper requestWrapper, Apex_Log__c apexLog) {
        String userId = requestWrapper.userId;
        String propertyId = requestWrapper.propertyId;

        if (String.isBlank(userId) || String.isBlank(propertyId)) {
            apexLog.response__c = 'UserId or propertyId should not be blank';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('UserId or propertyId should not be blank');
            return;
        }

        List<Customer_Master__c> customerMasterList = [SELECT Id, Name FROM Customer_Master__c WHERE Name = :userId AND isActive__c = TRUE LIMIT 1];
        if (customerMasterList.isEmpty()) {
            apexLog.response__c = 'Customer Not Found';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Customer Not Found');
            return;
        }

        // Match by OP-xxx (Name__c) for this customer
        List<Property__c> existingPropertyList = [SELECT Id, Name__c FROM Property__c WHERE Name__c = :propertyId AND Customer_Master__c = :customerMasterList[0].Id LIMIT 1];
        if (existingPropertyList.isEmpty()) {
            apexLog.response__c = 'Property Not Found';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Property Not Found');
            return;
        }

        Property__c property = new Property__c();
        property.Id = existingPropertyList[0].Id;
        property.Name = requestWrapper.propertyName;
        property.Property_Type__c = requestWrapper.propertyType;
        property.Property_Value__c = Decimal.valueOf(requestWrapper.propertyValue);
        property.Area__c = requestWrapper.areaType;
        property.Area1__c = Decimal.valueOf(requestWrapper.area);
        property.Dealer_Builder_Name__c = requestWrapper.dealerName;
        property.Survay__c = requestWrapper.surveyNo;
        property.Purchase_Date__c = requestWrapper.purchaseDate;

        update property;

        Property__c saved = [SELECT Name, Name__c, Property_Image_URl__c FROM Property__c WHERE Id = :existingPropertyList[0].Id LIMIT 1];

        apexLog.response__c = 'Property Updated successfully ' + saved.Name__c;
        apexLog.Status__c = 'SUCCESS';
        insert apexLog;

        sendActionResponse('Property Updated successfully', saved.Name__c, saved.Name, saved.Property_Image_URl__c != null ? saved.Property_Image_URl__c : '');
    }

    // ---------------------------------------------------------------- DELETE (soft, no notification)
    // Sets Status__c = 'Deleted' so the UI no longer shows it; record is retained.
    private static void handleDelete(PropertyWrapper requestWrapper, Apex_Log__c apexLog) {
        String userId = requestWrapper.userId;
        String propertyId = requestWrapper.propertyId;

        if (String.isBlank(userId) || String.isBlank(propertyId)) {
            apexLog.response__c = 'UserId or propertyId should not be blank';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('UserId or propertyId should not be blank');
            return;
        }

        List<Customer_Master__c> customerMasterList = [SELECT Id, Name FROM Customer_Master__c WHERE Name = :userId AND isActive__c = TRUE LIMIT 1];
        if (customerMasterList.isEmpty()) {
            apexLog.response__c = 'Customer Not Found';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Customer Not Found');
            return;
        }

        List<Property__c> existingPropertyList = [SELECT Id, Name, Name__c, Status__c, Property_Image_URl__c FROM Property__c WHERE Name__c = :propertyId AND Customer_Master__c = :customerMasterList[0].Id LIMIT 1];
        if (existingPropertyList.isEmpty()) {
            apexLog.response__c = 'Property Not Found';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Property Not Found');
            return;
        }

        if (existingPropertyList[0].Status__c == 'Deleted') {
            apexLog.response__c = 'Property is already deleted';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Property is already deleted');
            return;
        }

        Property__c property = new Property__c();
        property.Id = existingPropertyList[0].Id;
        property.Status__c = 'Deleted';
        update property;

        apexLog.response__c = 'Property deleted successfully ' + existingPropertyList[0].Name__c;
        apexLog.Status__c = 'SUCCESS';
        insert apexLog;

        sendActionResponse('Property deleted successfully', existingPropertyList[0].Name__c, existingPropertyList[0].Name, existingPropertyList[0].Property_Image_URl__c != null ? existingPropertyList[0].Property_Image_URl__c : '');
    }

    // ------------------------------------------------------------------ LIST (customer's own, excludes Deleted)
    private static void handleList(PropertyWrapper requestWrapper, Apex_Log__c apexLog) {
        String userId = requestWrapper.userId;

        if (String.isBlank(userId)) {
            apexLog.response__c = 'UserId should not be blank';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('UserId should not be blank');
            return;
        }

        List<Customer_Master__c> customerMasterList = [SELECT Id, Name FROM Customer_Master__c WHERE Name = :userId AND isActive__c = TRUE LIMIT 1];
        if (customerMasterList.isEmpty()) {
            apexLog.response__c = 'Customer Not Found';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Customer Not Found');
            return;
        }

        Integer effectivePageSize = (requestWrapper.pageSize != null && requestWrapper.pageSize > 0) ? Integer.valueOf(requestWrapper.pageSize) : 20;
        Integer effectivePageNumber = (requestWrapper.pageNumber != null && requestWrapper.pageNumber > 0) ? Integer.valueOf(requestWrapper.pageNumber) : 1;
        Integer recordOffset = (effectivePageNumber - 1) * effectivePageSize;

        if (recordOffset > 2000) {
            apexLog.response__c = 'Page range exceeded. Please refine your filters.';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Page range exceeded. Please refine your filters.');
            return;
        }

        List<Property__c> propertyList = [SELECT Id, Name, Name__c, Property_Type__c, Property_Value__c, Area__c, Area1__c, Dealer_Builder_Name__c, Survay__c, Purchase_Date__c, Status__c, Property_Image_URl__c, Customer_Master__r.Phone__c FROM Property__c WHERE Customer_Master__c = :customerMasterList[0].Id AND Status__c != 'Deleted' ORDER BY CreatedDate DESC LIMIT :effectivePageSize OFFSET :recordOffset];

        PropertyListResponse response = new PropertyListResponse();
        response.success = true;
        response.message = 'Other Property List fetched successfully';
        response.data = new PropertyListData();
        response.data.properties = buildPropertyList(propertyList);

        apexLog.response__c = 'Other Property List fetched successfully for ' + userId;
        apexLog.Status__c = 'SUCCESS';
        insert apexLog;

        sendListResponse(response);
    }

    // Owner of the customer's Customer Delight record (via their booking).
    // Returns the standard record OwnerId of the most recent CD record, or null.
    private static Id getCustomerDelightRecordOwner(Id customerMasterId) {
        List<Customer_Delight__c> cdList = [SELECT Id, OwnerId__c FROM Customer_Delight__c WHERE Booking__r.Customer_Master__c = :customerMasterId ORDER BY CreatedDate DESC LIMIT 1];
        return cdList.isEmpty() ? null : cdList[0].OwnerId__c;
    }

    // ------------------------------------------------------------ UPLOAD / REPLACE IMAGE
    // Re-upload is automatic: any existing property image is deleted first, then the new
    // one is saved, published, and its URL stored on Property_Image_URl__c.
    private static void handleUploadImage(PropertyWrapper requestWrapper, Apex_Log__c apexLog) {
        String userId = requestWrapper.userId;
        String propertyId = requestWrapper.propertyId;

        if (String.isBlank(userId) || String.isBlank(propertyId) || String.isBlank(requestWrapper.imageBase64)) {
            apexLog.response__c = 'UserId, propertyId & imageBase64 should not be blank';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('UserId, propertyId & imageBase64 should not be blank');
            return;
        }

        List<Property__c> propertyList = [SELECT Id, Name, Name__c FROM Property__c WHERE Name__c = :propertyId AND Customer_Master__r.Name = :userId LIMIT 1];
        if (propertyList.isEmpty()) {
            apexLog.response__c = 'Property Not Found';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Property Not Found');
            return;
        }

        Property__c property = propertyList[0];

        // Replace: remove any existing property image first
        deletePropertyImageFiles(property.Id);

        // Save the new image as a file on the property record
        String fileName = String.isNotBlank(requestWrapper.fileName) ? requestWrapper.fileName : ('property-image-' + property.Name__c + '.jpg');
        ContentVersion imageVersion = new ContentVersion();
        imageVersion.Title = fileName + ' [ Property Image ]';
        imageVersion.PathOnClient = fileName;
        imageVersion.VersionData = EncodingUtil.base64Decode(requestWrapper.imageBase64);
        imageVersion.FirstPublishLocationId = property.Id;   // links the file to the property
        insert imageVersion;

        // Public download URL for the app
        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :imageVersion.Id LIMIT 1].ContentDocumentId;
        ContentDistribution distribution = new ContentDistribution();
        distribution.Name = 'PropertyImage-' + property.Name__c;
        distribution.ContentVersionId = imageVersion.Id;
        distribution.PreferencesAllowViewInBrowser = true;
        distribution.PreferencesAllowOriginalDownload = true;
        insert distribution;

        String imageUrl = '';
        List<ContentDistribution> distList = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :distribution.Id LIMIT 1];
        if (!distList.isEmpty() && distList[0].ContentDownloadUrl != null) {
            imageUrl = distList[0].ContentDownloadUrl.replace('download/?', 'renditionDownload?rendition=ORIGINAL_Jpg&').replace('&ids', '&versionId');
        }

        Property__c toUpdate = new Property__c(Id = property.Id, Property_Image_URl__c = imageUrl);
        update toUpdate;

        apexLog.response__c = 'Image uploaded for ' + property.Name__c;
        apexLog.Status__c = 'SUCCESS';
        insert apexLog;

        sendActionResponse('Image uploaded successfully', property.Name__c, property.Name, imageUrl);
    }

    // ---------------------------------------------------------------- DELETE IMAGE
    private static void handleDeleteImage(PropertyWrapper requestWrapper, Apex_Log__c apexLog) {
        String userId = requestWrapper.userId;
        String propertyId = requestWrapper.propertyId;

        if (String.isBlank(userId) || String.isBlank(propertyId)) {
            apexLog.response__c = 'UserId or propertyId should not be blank';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('UserId or propertyId should not be blank');
            return;
        }

        List<Property__c> propertyList = [SELECT Id, Name, Name__c FROM Property__c WHERE Name__c = :propertyId AND Customer_Master__r.Name = :userId LIMIT 1];
        if (propertyList.isEmpty()) {
            apexLog.response__c = 'Property Not Found';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Property Not Found');
            return;
        }

        Property__c property = propertyList[0];
        deletePropertyImageFiles(property.Id);

        Property__c toUpdate = new Property__c(Id = property.Id, Property_Image_URl__c = '');
        update toUpdate;

        apexLog.response__c = 'Image deleted for ' + property.Name__c;
        apexLog.Status__c = 'SUCCESS';
        insert apexLog;

        sendActionResponse('Image deleted successfully', property.Name__c, property.Name, '');
    }

    // Deletes every "[ Property Image ]" file linked to the property (used by both
    // deleteImage and the replace step of uploadImage).
    private static void deletePropertyImageFiles(Id propertyRecordId) {
        List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :propertyRecordId];
        if (links.isEmpty()) { return; }

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink link : links) { docIds.add(link.ContentDocumentId); }

        List<ContentDocument> imageDocs = [SELECT Id FROM ContentDocument WHERE Id IN :docIds AND Title LIKE '%[ Property Image ]%'];
        if (!imageDocs.isEmpty()) { delete imageDocs; }
    }

    // Shared list builder
    private static List<PropertyData> buildPropertyList(List<Property__c> propertyList) {
        List<PropertyData> propertyDataList = new List<PropertyData>();
        for (Property__c property : propertyList) {
            PropertyData propertyData = new PropertyData();
            propertyData.propertyId = property.Name__c;   // OP-xxx auto-number
            propertyData.propertyName = property.Name;
            propertyData.propertyType = property.Property_Type__c;
            propertyData.propertyValue = String.valueOf(property.Property_Value__c);
            propertyData.areaType = property.Area__c;
            propertyData.area = String.valueOf(property.Area1__c);
            propertyData.dealerName = property.Dealer_Builder_Name__c;
            propertyData.surveyNo = property.Survay__c;
            propertyData.purchaseDate = String.valueOf(property.Purchase_Date__c);
            propertyData.status = property.Status__c;
            propertyData.propertyImage = property.Property_Image_URl__c;
            propertyData.sellerContactNumber = (property.Customer_Master__r != null) ? property.Customer_Master__r.Phone__c : '';
            propertyDataList.add(propertyData);
        }
        return propertyDataList;
    }

    // --------------------------------------------------------------- WRAPPERS
    public class PropertyWrapper {
        public String action;
        public String userId;
        public String propertyId;      // OP-xxx (Name__c) for edit / delete
        public String propertyName;
        public String propertyType;
        public String propertyValue;
        public String area;
        public String areaType;
        public String dealerName;
        public String surveyNo;
        public DateTime purchaseDate;
        public Decimal pageSize;
        public Decimal pageNumber;
        public String fileName;        // uploadImage
        public String imageBase64;     // uploadImage
    }

    // GET form wrappers
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
    }

    public class PropertyListResponse {
        public Boolean success;
        public String message;
        public PropertyListData data;
    }
    public class PropertyListData {
        public List<PropertyData> properties;
    }
    public class PropertyData {
        public String propertyId;
        public String propertyName;
        public String propertyType;
        public String propertyValue;
        public String area;
        public String areaType;
        public String dealerName;
        public String surveyNo;
        public String purchaseDate;
        public String status;
        public String propertyImage;
        public String sellerContactNumber;
    }

    // Action response - carries the OP-xxx number in requestId
    public class ActionResponse {
        public Boolean success;
        public String message;
        public String requestId;
        public String propertyName;    // the typed property name (standard Name)
        public String imageUrl;        // uploadImage / deleteImage
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

    private static void sendActionResponse(String message, String opNumber, String propertyName, String imageUrl) {
        ActionResponse response = new ActionResponse();
        response.success = true;
        response.message = message;
        response.requestId = opNumber;
        response.propertyName = propertyName;
        response.imageUrl = imageUrl;

        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }
    private static void sendListResponse(PropertyListResponse response) {
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