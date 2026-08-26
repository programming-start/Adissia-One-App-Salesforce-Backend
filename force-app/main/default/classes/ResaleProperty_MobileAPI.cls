/**
 * Author     : Sivam V
 * Class Name : ResaleProperty_MobileAPI
 * API Name   : ResaleProperty API
 * REST Method: GET & POST
 * Purpose    : Resale flow for the Resale Property tab.
 *   GET  ?customerId=AID3147  -> purchasedProperties + resaleRequests (for OWN + RESALE tabs)
 *   POST { action, ... }      -> create / edit / withdraw a resale request.
 *                                Every create/edit/withdraw returns the resale auto-number
 *                                (e.g. RS-0090) in requestId, mandatory for the app.
 * Date       : 06/07/2026
 */
@RestResource(urlMapping='/ResalePropertyAPI/*')
global without sharing class ResaleProperty_MobileAPI {

    private static final String REGISTRATION_STAGE = 'Registration';

    // =============================================================== GET (lists)
    @HttpGet
    global static void getMyPropertiesAndResale() {
        RestRequest request = RestContext.request;
        Apex_Log__c log = new Apex_Log__c();
        log.Request_Type__c = 'ResaleProperty_MobileAPI';

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

            Id customerRecordId = cmList[0].Id;

            // Purchased properties = Registration-completed bookings of this customer
            List<PropertyData> purchasedProperties = new List<PropertyData>();
            for (Booking__c booking : [SELECT Id, Name, Project__c, Unit_NumberFor__c, Plot_Sq_ft__c, GRAND_TOTAL__c, Unit_Status__c FROM Booking__c WHERE Customer_Master__c = :customerRecordId AND Stage__c = :REGISTRATION_STAGE AND Registration_Done__c = TRUE ORDER BY Booking_Date__c DESC]) {
                PropertyData pd = new PropertyData();
                pd.bookingId = booking.Id;
                pd.bookingName = safe(booking.Name);
                pd.projectName = safe(booking.Project__c);
                pd.unitNumber = safe(booking.Unit_NumberFor__c);
                pd.squareFeet = booking.Plot_Sq_ft__c != null ? String.valueOf(booking.Plot_Sq_ft__c) : '';
                pd.totalAmount = booking.GRAND_TOTAL__c != null ? String.valueOf(booking.GRAND_TOTAL__c) : '';
                pd.status = safe(booking.Unit_Status__c);
                purchasedProperties.add(pd);
            }

            // Resale requests raised by this customer
            List<ResaleData> resaleRequests = new List<ResaleData>();
            for (Re_Sale_Property__c resale : [SELECT Id, Name, Status__c, Seller_Price__c, Approved_Selling_Price__c, Description__c, Booking__c, Booking__r.Name, CreatedDate FROM Re_Sale_Property__c WHERE Customer_Master__c = :customerRecordId ORDER BY CreatedDate DESC]) {
                ResaleData rd = new ResaleData();
                rd.resaleId = resale.Name;
                rd.status = safe(resale.Status__c);
                rd.sellerPrice = resale.Seller_Price__c != null ? String.valueOf(resale.Seller_Price__c) : '';
                rd.approvedPrice = resale.Approved_Selling_Price__c != null ? String.valueOf(resale.Approved_Selling_Price__c) : '';
                rd.description = safe(resale.Description__c);
                rd.bookingName = resale.Booking__c != null ? safe(resale.Booking__r.Name) : '';
                rd.createdDate = String.valueOf(resale.CreatedDate);
                resaleRequests.add(rd);
            }

            MyPropertiesResponse response = new MyPropertiesResponse();
            response.success = true;
            response.message = 'Data fetched successfully';
            response.data = new MyPropertiesData();
            response.data.purchasedProperties = purchasedProperties;
            response.data.resaleRequests = resaleRequests;

            log.response__c = 'Purchased properties + resale requests fetched for ' + customerId;
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

    // =============================================================== POST (actions)
    @HttpPost
    global static void handleResaleRequest() {
        RestRequest request = RestContext.request;
        String requestBody = request.requestBody.toString(); // Get the JSON body
        Apex_Log__c apexLog = new Apex_Log__c();
        apexLog.Request_Type__c = 'ResaleProperty_MobileAPI';
        apexLog.Request__c = requestBody;

        try {
            ResaleWrapper requestWrapper = (ResaleWrapper) JSON.deserialize(requestBody, ResaleWrapper.class);
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
            } else if (action == 'withdraw') {
                handleWithdraw(requestWrapper, apexLog);
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

    // ---------------------------------------------------------------- CREATE (Request for Sale)
    // Popup collects seller price + description; bookingId identifies the property.
    // Resale price must be greater than the plot's Total Cost. Returns the resale number.
    private static void handleCreate(ResaleWrapper requestWrapper, Apex_Log__c apexLog) {
        String customerNumber = requestWrapper.userId;
        String bookingNumber = requestWrapper.bookingId;
        String description = requestWrapper.description;
        String sellerPrice = requestWrapper.price;

        if (String.isBlank(customerNumber) || String.isBlank(bookingNumber) || String.isBlank(description) || String.isBlank(sellerPrice)) {
            apexLog.response__c = 'UserId, BookingId, Description & Price should not be blank';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('UserId, BookingId, Description & Price should not be blank');
            return;
        }

        List<Customer_Master__c> customerMasterList = [SELECT Id, Name FROM Customer_Master__c WHERE Name = :customerNumber AND isActive__c = TRUE LIMIT 1];
        if (customerMasterList.isEmpty()) {
            apexLog.response__c = 'Customer Not Found';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Customer Not Found');
            return;
        }

        List<Booking__c> bookingList = [SELECT Id, Name, Plot__r.Total_Cost__c FROM Booking__c WHERE Name = :bookingNumber AND Customer_Master__c = :customerMasterList[0].Id LIMIT 1];
        if (bookingList.isEmpty()) {
            apexLog.response__c = 'Booking Not Found for this customer';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Booking Not Found for this customer');
            return;
        }

        Decimal newSellerPrice = Decimal.valueOf(sellerPrice);
        Decimal plotTotalCost = bookingList[0].Plot__r != null ? bookingList[0].Plot__r.Total_Cost__c : null;

        if (plotTotalCost != null && newSellerPrice <= plotTotalCost) {
            apexLog.response__c = 'Resale price must be greater than the land total cost of ' + String.valueOf(plotTotalCost);
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Resale price must be greater than the land total cost of ' + String.valueOf(plotTotalCost));
            return;
        }

        // One active listing per plot - block if a non-cancelled resale already exists
        List<Re_Sale_Property__c> existingResaleList = [SELECT Id, Name FROM Re_Sale_Property__c WHERE Customer_Master__c = :customerMasterList[0].Id AND Booking__c = :bookingList[0].Id AND Status__c != 'Cancelled'];
        if (!existingResaleList.isEmpty()) {
            apexLog.response__c = 'Re-sale Record Already Exists for the selected Booking';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Re-sale Record Already Exists for the selected Booking');
            return;
        }

        Re_Sale_Property__c resaleProperty = new Re_Sale_Property__c();
        resaleProperty.Customer_Master__c = customerMasterList[0].Id;
        resaleProperty.Booking__c = bookingList[0].Id;
        resaleProperty.Description__c = description;
        resaleProperty.Seller_Price__c = newSellerPrice;
        resaleProperty.Status__c = 'Pending for Approval';

        Id resaleOwnerId = ReSaleNotifier.getResaleOwnerId();
        if (resaleOwnerId != null) {
            resaleProperty.OwnerId = resaleOwnerId;
        }

        insert resaleProperty;

        ReSaleNotifier.notifyCreated(resaleProperty.Id, resaleOwnerId);

        // Read back the auto-number to return to the app
        Re_Sale_Property__c created = [SELECT Name FROM Re_Sale_Property__c WHERE Id = :resaleProperty.Id LIMIT 1];

        apexLog.response__c = 'Resale request created successfully by ' + customerNumber + ' : ' + created.Name;
        apexLog.Status__c = 'SUCCESS';
        insert apexLog;

        sendSuccessResponse('Resale request created successfully', created.Name);
    }

    // ------------------------------------------------------------------ EDIT (price + description only)
    private static void handleEdit(ResaleWrapper requestWrapper, Apex_Log__c apexLog) {
        String resaleId = requestWrapper.resaleId;
        String userId = requestWrapper.userId;
        String description = requestWrapper.description;
        String price = requestWrapper.price;

        if (String.isBlank(resaleId) || String.isBlank(userId) || String.isBlank(description) || String.isBlank(price)) {
            apexLog.response__c = 'ResaleId, UserId, Description & Price should not be blank';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('ResaleId, UserId, Description & Price should not be blank');
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

        List<Re_Sale_Property__c> matchingResaleList = [SELECT Id, Name, Description__c, Seller_Price__c, Status__c, OwnerId, Booking__r.Plot__r.Total_Cost__c FROM Re_Sale_Property__c WHERE Name = :resaleId AND Customer_Master__c = :customerMasterList[0].Id LIMIT 1];
        if (matchingResaleList.isEmpty()) {
            apexLog.response__c = 'No Re-Sale record found matching the provided parameters.';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('No Re-Sale record found matching the provided parameters.');
            return;
        }

        Re_Sale_Property__c existingResale = matchingResaleList[0];

        if (existingResale.Status__c == 'Cancelled' || existingResale.Status__c == 'Requested for Cancellation') {
            apexLog.response__c = 'Cannot edit the Re-Sale record as it is cancelled or requested for cancellation.';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Cannot edit the Re-Sale record as it is cancelled or requested for cancellation.');
            return;
        }

        Decimal newSellerPrice = Decimal.valueOf(price);
        Decimal plotTotalCost = (existingResale.Booking__r != null && existingResale.Booking__r.Plot__r != null) ? existingResale.Booking__r.Plot__r.Total_Cost__c : null;

        if (plotTotalCost != null && newSellerPrice <= plotTotalCost) {
            apexLog.response__c = 'Resale price must be greater than the land total cost of ' + String.valueOf(plotTotalCost);
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Resale price must be greater than the land total cost of ' + String.valueOf(plotTotalCost));
            return;
        }

        String previousDescription = existingResale.Description__c;
        Decimal previousSellerPrice = existingResale.Seller_Price__c;
        Id recordOwnerId = existingResale.OwnerId;

        List<String> changedFieldLines = new List<String>();
        if (previousDescription != description) {
            changedFieldLines.add('Description  : ' + previousDescription + '  ->  ' + description);
        }
        if (previousSellerPrice != newSellerPrice) {
            changedFieldLines.add('Seller Price : ' + String.valueOf(previousSellerPrice) + '  ->  ' + String.valueOf(newSellerPrice));
        }

        if (changedFieldLines.isEmpty()) {
            apexLog.response__c = 'No changes found. Resale record not updated.';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendSuccessResponse('Resale Updated successfully', existingResale.Name);
            return;
        }

        Re_Sale_Property__c resaleToUpdate = new Re_Sale_Property__c();
        resaleToUpdate.Id = existingResale.Id;
        resaleToUpdate.Description__c = description;
        resaleToUpdate.Seller_Price__c = newSellerPrice;
        update resaleToUpdate;

        ReSaleNotifier.notifyUpdated(existingResale.Id, recordOwnerId, changedFieldLines);

        apexLog.response__c = 'Resale Updated successfully : ' + existingResale.Name;
        apexLog.Status__c = 'SUCCESS';
        insert apexLog;

        sendSuccessResponse('Resale Updated successfully', existingResale.Name);
    }

    // ---------------------------------------------------------------- WITHDRAW
    private static void handleWithdraw(ResaleWrapper requestWrapper, Apex_Log__c apexLog) {
        String resaleId = requestWrapper.resaleId;
        String userId = requestWrapper.userId;

        if (String.isBlank(resaleId) || String.isBlank(userId)) {
            apexLog.response__c = 'ResaleId & UserId should not be blank';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('ResaleId & UserId should not be blank');
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

        List<Re_Sale_Property__c> blockedResaleList = [SELECT Id, Name FROM Re_Sale_Property__c WHERE Name = :resaleId AND (Status__c = 'Cancelled' OR Status__c = 'Requested for Cancellation') LIMIT 1];
        if (!blockedResaleList.isEmpty()) {
            apexLog.response__c = 'Cannot withdraw the Re-Sale record as it is already cancelled or already requested for cancellation.';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('Cannot withdraw the Re-Sale record as it is already cancelled or already requested for cancellation.');
            return;
        }

        List<Re_Sale_Property__c> matchingResaleList = [SELECT Id, Name, Status__c, OwnerId FROM Re_Sale_Property__c WHERE Name = :resaleId AND Customer_Master__c = :customerMasterList[0].Id LIMIT 1];
        if (matchingResaleList.isEmpty()) {
            apexLog.response__c = 'No Re-Sale record found matching the provided parameters.';
            apexLog.Status__c = 'SUCCESS';
            insert apexLog;
            sendErrorResponse('No Re-Sale record found matching the provided parameters.');
            return;
        }

        Re_Sale_Property__c existingResale = matchingResaleList[0];
        Id recordOwnerId = existingResale.OwnerId;

        Re_Sale_Property__c resaleToUpdate = new Re_Sale_Property__c();
        resaleToUpdate.Id = existingResale.Id;
        resaleToUpdate.Status__c = 'Requested for Cancellation';
        update resaleToUpdate;

        ReSaleNotifier.notifyDeleted(existingResale.Id, recordOwnerId);

        apexLog.response__c = 'Resale withdrawal requested successfully : ' + existingResale.Name;
        apexLog.Status__c = 'SUCCESS';
        insert apexLog;

        sendSuccessResponse('Resale withdrawal requested successfully', existingResale.Name);
    }

    private static String safe(String value) {
        return value == null ? '' : value;
    }

    // --------------------------------------------------------------- WRAPPERS
    public class ResaleWrapper {
        public String action;
        public String resaleId;
        public String userId;
        public String bookingId;
        public String description;
        public String price;
    }

    // GET list wrappers
    public class MyPropertiesResponse {
        public Boolean success;
        public String message;
        public MyPropertiesData data;
    }
    public class MyPropertiesData {
        public List<PropertyData> purchasedProperties;
        public List<ResaleData> resaleRequests;
    }
    public class PropertyData {
        public String bookingId;
        public String bookingName;
        public String projectName;
        public String unitNumber;
        public String squareFeet;
        public String totalAmount;
        public String status;
    }
    public class ResaleData {
        public String resaleId;
        public String status;
        public String sellerPrice;
        public String approvedPrice;
        public String description;
        public String bookingName;
        public String createdDate;
    }

    // POST action response - carries the resale number in requestId
    public class ActionResponse {
        public Boolean success;
        public String message;
        public String requestId;
    }
    private static void sendSuccessResponse(String message, String resaleNumber) {
        ActionResponse response = new ActionResponse();
        response.success = true;
        response.message = message;
        response.requestId = resaleNumber;

        RestContext.response.statusCode = 200;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }
    private static void sendErrorResponse(String message) {
        ActionResponse response = new ActionResponse();
        response.success = false;
        response.message = message;

        RestContext.response.statusCode = 400;
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }
}